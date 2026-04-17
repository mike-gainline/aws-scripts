#!/bin/bash

###############################################################################
# Portfolio RDS Manager - Deployment Script
#
# This script sets up the complete infrastructure:
#   1. CloudFormation stack (DynamoDB, SNS, IAM, Lambda, EventBridge)
#   2. Lambda function code deployment
#   3. S3 config bucket initialization
#   4. Initial state verification
#
# Usage:
#   ./deploy-portfolio-rds.sh [email-for-notifications]
#   ./deploy-portfolio-rds.sh your-email@example.com
#
# Prerequisites:
#   - AWS CLI configured with credentials
#   - jq installed for JSON parsing
#   - yq installed for YAML parsing
###############################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="portfolio-rds-manager"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

die() {
    log_error "$@"
    exit 1
}

check_dependencies() {
    local missing=()
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing+=("yq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  brew install awscli jq yq  # macOS"
        echo "  sudo apt-get install awscli jq yq  # Ubuntu"
        exit 1
    fi
}

verify_aws_credentials() {
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        die "AWS credentials not configured. Run: aws configure"
    fi
    
    log_success "AWS credentials verified (Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION)"
}

###############################################################################
# Deployment Functions
###############################################################################

deploy_cloudformation() {
    local email="${1:-}"
    
    log_info "Deploying CloudFormation stack: $STACK_NAME"
    
    local params=""
    if [ -n "$email" ]; then
        params="--parameter-overrides NotificationEmail=$email"
    fi
    
    if ! aws cloudformation deploy \
        --template-file "$SCRIPT_DIR/portfolio-rds-cf.yaml" \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --capabilities CAPABILITY_NAMED_IAM \
        $params \
        --no-fail-on-empty-changeset; then
        die "CloudFormation deployment failed"
    fi
    
    log_success "CloudFormation stack deployed"
}

get_stack_outputs() {
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs' \
        --output json
}

deploy_lambda_code() {
    log_info "Packaging and deploying Lambda function code..."
    
    # Create Lambda deployment package
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Copy Lambda function
    cp "$SCRIPT_DIR/lambda-auto-restart.py" "$temp_dir/index.py"
    
    # Create zip
    cd "$temp_dir"
    zip -q lambda-function.zip index.py
    
    # Get Lambda function name from stack
    local lambda_name=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
        --output text)
    
    if [ -z "$lambda_name" ]; then
        die "Could not find Lambda function name in CloudFormation outputs"
    fi
    
    # Update Lambda code
    if aws lambda update-function-code \
        --function-name "$lambda_name" \
        --region "$AWS_REGION" \
        --zip-file "fileb://lambda-function.zip" > /dev/null 2>&1; then
        log_success "Lambda function code deployed: $lambda_name"
    else
        die "Failed to deploy Lambda code"
    fi
    
    cd - > /dev/null
}

upload_config_to_s3() {
    log_info "Uploading configuration to S3..."
    
    local config_bucket=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ConfigBucketName`].OutputValue' \
        --output text)
    
    if [ -z "$config_bucket" ]; then
        die "Could not find S3 bucket in CloudFormation outputs"
    fi
    
    # Update config with actual account ID and bucket name
    sed "s/311330778203/$AWS_ACCOUNT_ID/g" "$SCRIPT_DIR/rds-portfolio-config.yaml" > /tmp/config-updated.yaml
    sed -i "s/portfolio-db-backups-[0-9]*/portfolio-db-backups-$AWS_ACCOUNT_ID/g" /tmp/config-updated.yaml
    
    aws s3 cp /tmp/config-updated.yaml "s3://$config_bucket/rds-portfolio-config.yaml" \
        --region "$AWS_REGION" || die "Failed to upload config to S3"
    
    log_success "Configuration uploaded to S3: s3://$config_bucket/rds-portfolio-config.yaml"
}

create_backup_bucket() {
    log_info "Creating S3 bucket for database backups..."
    
    local backup_bucket="portfolio-db-backups-$AWS_ACCOUNT_ID"
    
    if aws s3 ls "s3://$backup_bucket" 2>/dev/null; then
        log_warning "Backup bucket already exists: $backup_bucket"
    else
        if aws s3 mb "s3://$backup_bucket" --region "$AWS_REGION"; then
            # Enable versioning
            aws s3api put-bucket-versioning \
                --bucket "$backup_bucket" \
                --versioning-configuration Status=Enabled \
                --region "$AWS_REGION"
            
            # Enable encryption
            aws s3api put-bucket-encryption \
                --bucket "$backup_bucket" \
                --server-side-encryption-configuration '{
                    "Rules": [{
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }]
                }' \
                --region "$AWS_REGION"
            
            # Block public access
            aws s3api put-public-access-block \
                --bucket "$backup_bucket" \
                --public-access-block-configuration \
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
                --region "$AWS_REGION"
            
            log_success "Backup bucket created: s3://$backup_bucket"
        else
            die "Failed to create backup bucket"
        fi
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check DynamoDB table
    if aws dynamodb describe-table \
        --table-name "portfolio-rds-state" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "DynamoDB table ready"
    else
        die "DynamoDB table not found"
    fi
    
    # Check Lambda function
    local lambda_name=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
        --output text)
    
    if aws lambda get-function --function-name "$lambda_name" --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Lambda function deployed: $lambda_name"
    else
        die "Lambda function not found"
    fi
    
    # Check EventBridge rule
    if aws events describe-rule \
        --name "portfolio-rds-auto-restart-schedule" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "EventBridge rule configured"
    else
        die "EventBridge rule not found"
    fi
    
    echo ""
    log_success "All components deployed successfully!"
}

print_next_steps() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      DEPLOYMENT COMPLETE                                  ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📋 Next Steps:"
    echo ""
    echo "1. Update RDS instance details in config:"
    echo "   • Edit rds-portfolio-config.yaml"
    echo "   • Update vpc_security_groups IDs for each instance"
    echo "   • Update database usernames/passwords"
    echo "   • Upload updated config: aws s3 cp rds-portfolio-config.yaml s3://portfolio-rds-config-$AWS_ACCOUNT_ID/"
    echo ""
    echo "2. Test the CLI tool:"
    echo "   chmod +x portfolio-rds-manager.sh"
    echo "   ./portfolio-rds-manager.sh list"
    echo "   ./portfolio-rds-manager.sh status"
    echo ""
    echo "3. Try a test stop/start:"
    echo "   ./portfolio-rds-manager.sh stop bloom-prototype"
    echo "   ./portfolio-rds-manager.sh start bloom-prototype"
    echo ""
    echo "4. Lambda automation is now active!"
    echo "   • Checks every 6 hours for stopped instances"
    echo "   • Auto-restarts at 7-day mark to avoid AWS reset"
    echo "   • Sends SNS notifications when restarting"
    echo ""
    echo "📊 Cost Estimates:"
    echo "   • stop-start strategy: ~$13/month per instance (50% savings)"
    echo "   • delete-restore strategy: ~$0.13/month per instance (98% savings)"
    echo ""
    echo "   View all estimates:"
    echo "   ./portfolio-rds-manager.sh cost-estimate"
    echo ""
    echo "📚 Documentation:"
    echo "   See README-PORTFOLIO-RDS.md for complete reference"
    echo ""
}

###############################################################################
# Main
###############################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║          Portfolio RDS Manager - Deployment Script                         ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_dependencies
    verify_aws_credentials
    
    # Get email if not provided
    local email="${1:-}"
    if [ -z "$email" ]; then
        read -p "📧 Enter email for SNS notifications (optional, press Enter to skip): " email
    fi
    
    echo ""
    log_info "Starting deployment..."
    echo "  Account: $AWS_ACCOUNT_ID"
    echo "  Region: $AWS_REGION"
    echo "  Stack: $STACK_NAME"
    if [ -n "$email" ]; then
        echo "  Notifications: $email"
    fi
    echo ""
    
    # Proceed with deployment
    deploy_cloudformation "$email"
    deploy_lambda_code
    upload_config_to_s3
    create_backup_bucket
    verify_deployment
    print_next_steps
}

main "$@"
