"""
Portfolio RDS Auto-Restart Lambda Function

This Lambda runs on a schedule (via EventBridge) and:
1. Checks all stopped RDS instances from config
2. Tracks how long they've been stopped using DynamoDB
3. Auto-restarts instances at the 7-day mark (AWS max stop duration)
4. Sends SNS notifications when restarting
5. Prevents unexpected auto-resume charges

Triggered by: EventBridge schedule expression (cron: 0 */6 * * ? *)
Environment variables:
  CONFIG_BUCKET: S3 bucket containing rds-portfolio-config.yaml
  STATE_TABLE: DynamoDB table for tracking stop times
  SNS_TOPIC_ARN: SNS topic for notifications
"""

import json
import boto3
import os
import time
from datetime import datetime, timedelta
from typing import Dict, List, Tuple

# AWS clients
rds = boto3.client('rds')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
sns = boto3.client('sns')

# Environment variables
STATE_TABLE_NAME = os.environ.get('STATE_TABLE', 'portfolio-rds-state')
CONFIG_S3_BUCKET = os.environ.get('CONFIG_BUCKET', 'portfolio-config')
CONFIG_KEY = 'rds-portfolio-config.yaml'
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
REGION = os.environ.get('AWS_REGION', 'us-east-1')

# Constants
MAX_STOP_DURATION_DAYS = 7
RESTART_BUFFER_HOURS = 1  # Restart with 1 hour buffer before 7-day limit


class ConfigLoader:
    """Load and parse YAML config from S3"""
    
    @staticmethod
    def load() -> Dict:
        """Load config from S3"""
        try:
            response = s3.get_object(Bucket=CONFIG_S3_BUCKET, Key=CONFIG_KEY)
            config_text = response['Body'].read().decode('utf-8')
            return ConfigLoader._parse_yaml(config_text)
        except Exception as e:
            print(f"Error loading config: {e}")
            return {}
    
    @staticmethod
    def _parse_yaml(yaml_text: str) -> Dict:
        """Simple YAML parser for our specific use case"""
        # For production, use pyyaml library
        # This is a minimal parser that works for our config structure
        config = {'instances': []}
        current_instance = None
        
        for line in yaml_text.split('\n'):
            line = line.rstrip()
            
            # Skip comments and empty lines
            if not line or line.strip().startswith('#'):
                continue
            
            # Instance section
            if line.startswith('  - name:'):
                if current_instance:
                    config['instances'].append(current_instance)
                name_value = line.split(':', 1)[1].strip().strip('"\'')
                current_instance = {'name': name_value}
                continue
            
            # Instance properties
            if current_instance and line.startswith('    '):
                key, value = line.split(':', 1)
                key = key.strip()
                value = value.strip().strip("'\"")
                current_instance[key] = value
        
        if current_instance:
            config['instances'].append(current_instance)
        
        return config


class StateManager:
    """Manage RDS instance state in DynamoDB"""
    
    def __init__(self):
        self.table = dynamodb.Table(STATE_TABLE_NAME)
    
    def get_stop_time(self, instance_name: str) -> datetime | None:
        """Get when instance was stopped"""
        try:
            response = self.table.get_item(
                Key={'instance_name': instance_name}
            )
            if 'Item' in response:
                timestamp_str = response['Item'].get('stop_timestamp')
                if timestamp_str:
                    return datetime.fromisoformat(timestamp_str)
        except Exception as e:
            print(f"Error reading stop time for {instance_name}: {e}")
        
        return None
    
    def set_stop_time(self, instance_name: str, stop_time: datetime = None):
        """Record when instance was stopped"""
        if stop_time is None:
            stop_time = datetime.utcnow()
        
        try:
            self.table.put_item(
                Item={
                    'instance_name': instance_name,
                    'stop_timestamp': stop_time.isoformat(),
                    'last_updated': datetime.utcnow().isoformat(),
                    'auto_restart_enabled': True,
                }
            )
            print(f"Recorded stop time for {instance_name}: {stop_time.isoformat()}")
        except Exception as e:
            print(f"Error saving stop time for {instance_name}: {e}")
    
    def clear_stop_time(self, instance_name: str):
        """Clear stop record (instance restarted)"""
        try:
            self.table.delete_item(Key={'instance_name': instance_name})
            print(f"Cleared stop time for {instance_name}")
        except Exception as e:
            print(f"Error clearing stop time for {instance_name}: {e}")


class RDSManager:
    """Manage RDS instance operations"""
    
    @staticmethod
    def get_instance_status(db_identifier: str) -> str:
        """Get current RDS instance status"""
        try:
            response = rds.describe_db_instances(
                DBInstanceIdentifier=db_identifier
            )
            if response['DBInstances']:
                return response['DBInstances'][0]['DBInstanceStatus']
        except rds.exceptions.DBInstanceNotFoundFault:
            return 'deleted'
        except Exception as e:
            print(f"Error getting status for {db_identifier}: {e}")
        
        return 'unknown'
    
    @staticmethod
    def start_instance(db_identifier: str) -> bool:
        """Start a stopped RDS instance"""
        try:
            print(f"Starting RDS instance: {db_identifier}")
            rds.start_db_instance(DBInstanceIdentifier=db_identifier)
            return True
        except Exception as e:
            print(f"Error starting {db_identifier}: {e}")
            return False

    @staticmethod
    def wait_until_available(db_identifier: str, timeout_seconds: int = 600) -> bool:
        """Poll until instance is available, up to timeout_seconds"""
        print(f"  Waiting for {db_identifier} to become available (up to {timeout_seconds}s)...")
        deadline = time.time() + timeout_seconds
        poll_interval = 20
        while time.time() < deadline:
            status = RDSManager.get_instance_status(db_identifier)
            print(f"  Status: {status}")
            if status == 'available':
                return True
            if status in ('deleted', 'unknown'):
                print(f"  Unexpected status '{status}', aborting wait")
                return False
            time.sleep(poll_interval)
        print(f"  Timed out waiting for {db_identifier} to become available")
        return False

    @staticmethod
    def stop_instance(db_identifier: str) -> bool:
        """Stop a running RDS instance"""
        try:
            print(f"Stopping RDS instance: {db_identifier}")
            rds.stop_db_instance(DBInstanceIdentifier=db_identifier)
            return True
        except Exception as e:
            print(f"Error stopping {db_identifier}: {e}")
            return False


class Notifier:
    """Send notifications via SNS"""
    
    @staticmethod
    def send(subject: str, message: str, instance_name: str = ''):
        """Send SNS notification"""
        if not SNS_TOPIC_ARN:
            print(f"SNS not configured, skipping notification: {subject}")
            return
        
        try:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f"Portfolio RDS: {subject}",
                Message=f"""
Instance: {instance_name}
Time: {datetime.utcnow().isoformat()}

{message}

---
Auto-managed by portfolio-rds-manager Lambda
            """
            )
            print(f"Notification sent: {subject}")
        except Exception as e:
            print(f"Error sending notification: {e}")


def lambda_handler(event, context):
    """
    Main Lambda handler - runs on schedule to check and restart instances
    """
    print("=" * 80)
    print("Portfolio RDS Auto-Restart Check")
    print(f"Started at: {datetime.utcnow().isoformat()}")
    print("=" * 80)
    
    # Load configuration
    config = ConfigLoader.load()
    if not config or not config.get('instances'):
        return {
            'statusCode': 400,
            'body': json.dumps('No instances configured')
        }
    
    state_manager = StateManager()
    rds_manager = RDSManager()
    
    restart_count = 0
    error_count = 0
    
    # Check each configured instance
    for instance_config in config.get('instances', []):
        instance_name = instance_config.get('name')
        db_identifier = instance_config.get('db_identifier')
        
        print(f"\nChecking: {instance_name} ({db_identifier})")
        
        try:
            # Get current status
            status = rds_manager.get_instance_status(db_identifier)
            print(f"  Status: {status}")
            
            # If not stopped, skip
            if status != 'stopped':
                print(f"  Not stopped, skipping")
                continue
            
            # Get when it was stopped
            stop_time = state_manager.get_stop_time(instance_name)
            
            if not stop_time:
                print(f"  No stop record found, recording current stop")
                state_manager.set_stop_time(instance_name)
                continue
            
            # Calculate how long it's been stopped
            now = datetime.utcnow()
            duration = now - stop_time
            days_stopped = duration.total_seconds() / 86400
            
            print(f"  Stopped since: {stop_time.isoformat()}")
            print(f"  Duration: {days_stopped:.1f} days")
            
            # Check if approaching 7-day limit
            restart_threshold = MAX_STOP_DURATION_DAYS - (RESTART_BUFFER_HOURS / 24)
            
            if days_stopped >= restart_threshold:
                print(f"  ⚠️  Approaching 7-day limit! Restarting...")
                
                # Start the instance, wait for available, then stop it again
                if rds_manager.start_instance(db_identifier):
                    if rds_manager.wait_until_available(db_identifier):
                        if rds_manager.stop_instance(db_identifier):
                            restart_count += 1
                            # Record fresh stop time for next 7-day cycle
                            state_manager.set_stop_time(instance_name)
                            print(f"  ✓ Instance cycled (start → stop) successfully")
                            Notifier.send(
                                f"Auto-cycled {instance_name} (still stopped)",
                                f"The RDS instance {instance_name} was briefly started to reset "
                                f"AWS's 7-day stop limit, then immediately stopped again.\n\n"
                                f"Instance: {db_identifier}\n"
                                f"Duration stopped: {days_stopped:.1f} days\n"
                                f"Action: RESTARTED then RE-STOPPED\n\n"
                                f"No action needed — charges remain minimal.",
                                instance_name
                            )
                        else:
                            # Started but failed to re-stop — still record, notify
                            restart_count += 1
                            state_manager.clear_stop_time(instance_name)
                            print(f"  ⚠️  Started but failed to re-stop — instance is running")
                            Notifier.send(
                                f"WARNING: {instance_name} is running — stop it manually",
                                f"The RDS instance {instance_name} was started to reset the 7-day "
                                f"limit but could NOT be automatically stopped.\n\n"
                                f"Instance: {db_identifier}\n"
                                f"Action needed: stop it to avoid charges:\n"
                                f"  ./portfolio-rds-manager.sh stop {instance_name}",
                                instance_name
                            )
                    else:
                        # Started but never became available within timeout
                        error_count += 1
                        state_manager.clear_stop_time(instance_name)
                        print(f"  ✗ Instance started but didn't become available in time")
                        Notifier.send(
                            f"WARNING: {instance_name} status unknown — check manually",
                            f"The RDS instance {instance_name} was started to reset the 7-day "
                            f"limit but did not reach 'available' within the wait window.\n\n"
                            f"Instance: {db_identifier}\n"
                            f"Please check its status and stop it if running:\n"
                            f"  ./portfolio-rds-manager.sh status\n"
                            f"  ./portfolio-rds-manager.sh stop {instance_name}",
                            instance_name
                        )
                else:
                    error_count += 1
                    print(f"  ✗ Failed to start instance")
            else:
                days_remaining = restart_threshold - days_stopped
                print(f"  OK - {days_remaining:.1f} days remaining before restart")
        
        except Exception as e:
            error_count += 1
            print(f"  ✗ Error processing {instance_name}: {e}")
    
    # Summary
    print("\n" + "=" * 80)
    print("Summary:")
    print(f"  Restarted: {restart_count}")
    print(f"  Errors: {error_count}")
    print(f"  Completed at: {datetime.utcnow().isoformat()}")
    print("=" * 80)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Auto-restart check completed',
            'restarted_count': restart_count,
            'error_count': error_count,
        })
    }


if __name__ == '__main__':
    # Local testing
    import sys
    sys.path.insert(0, '/opt/python')  # For local testing with local boto3
    
    # Mock event for testing
    event = {}
    context = None
    result = lambda_handler(event, context)
    print(json.dumps(result, indent=2))
