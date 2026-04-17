#!/bin/bash
# Start Bloom EC2 instance and verify services

set -e

INSTANCE_ID="i-038b8823f2ef5ea0e"
REGION="us-east-1"
PROFILE="housing-prototype"
SSH_KEY="$HOME/.ssh/bloom-prototype-key.pem"
PUBLIC_IP="3.222.204.115"

echo "🚀 Starting Bloom EC2 Instance"
echo "================================"
echo ""

# Check current state
echo "Checking current instance state..."
CURRENT_STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

echo "Current state: $CURRENT_STATE"
echo ""

if [ "$CURRENT_STATE" = "running" ]; then
    echo "✅ Instance is already running"
    echo "Checking services..."
else
    if [ "$CURRENT_STATE" != "stopped" ]; then
        echo "⚠️  Instance is in state: $CURRENT_STATE"
        echo "Cannot start instance in this state."
        exit 1
    fi

    # Start the instance
    echo "Starting instance..."
    aws ec2 start-instances \
      --instance-ids "$INSTANCE_ID" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --output table

    echo ""
    echo "⏳ Waiting for instance to start (this may take 30-60 seconds)..."
    aws ec2 wait instance-running \
      --instance-ids "$INSTANCE_ID" \
      --region "$REGION" \
      --profile "$PROFILE"

    echo ""
    echo "✅ Instance is now running!"
    echo ""
    echo "⏳ Waiting for system initialization (20 seconds)..."
    sleep 20
fi

# Check PM2 services
echo ""
echo "Checking PM2 services..."
ssh -i "$SSH_KEY" -o ConnectTimeout=10 ec2-user@"$PUBLIC_IP" 'pm2 list' || {
    echo "⚠️  Could not connect via SSH yet, services may still be starting..."
    echo "Try running this script again in 1-2 minutes, or check manually:"
    echo "  ssh -i $SSH_KEY ec2-user@$PUBLIC_IP 'pm2 list'"
    exit 0
}

# Check nginx
echo ""
echo "Checking nginx..."
ssh -i "$SSH_KEY" ec2-user@"$PUBLIC_IP" 'sudo systemctl status nginx --no-pager | head -5'

echo ""
echo "✅ All systems operational!"
echo ""
echo "💰 Cost Information:"
echo "   - EC2 compute: NOW charged ~$0.0416/hour (~$1/day)"
echo "   - EBS storage: Charged ~$0.05/day"
echo "   - Elastic IP: FREE while instance is running"
echo ""
echo "🌐 Your sites should be online in 1-2 minutes:"
echo "   - https://bloompublic.civicapplab.com"
echo "   - https://bloomportal.civicapplab.com"
echo "   - https://bloomapi.civicapplab.com"
echo ""
echo "💡 When done, save costs by running: ./bloom-stop.sh"
echo ""
