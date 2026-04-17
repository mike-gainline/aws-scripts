#!/bin/bash
# Stop Bloom EC2 instance to save costs

set -e

INSTANCE_ID="i-038b8823f2ef5ea0e"
REGION="us-east-1"
PROFILE="housing-prototype"

echo "🛑 Stopping Bloom EC2 Instance"
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

if [ "$CURRENT_STATE" = "stopped" ]; then
    echo "✅ Instance is already stopped"
    exit 0
fi

if [ "$CURRENT_STATE" != "running" ]; then
    echo "⚠️  Instance is in state: $CURRENT_STATE (not running)"
    echo "Cannot stop instance in this state."
    exit 1
fi

# Stop the instance
echo "Stopping instance..."
aws ec2 stop-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --output table

echo ""
echo "⏳ Waiting for instance to stop (this may take 30-60 seconds)..."
aws ec2 wait instance-stopped \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --profile "$PROFILE"

echo ""
echo "✅ Instance stopped successfully!"
echo ""
echo "💰 Cost Savings:"
echo "   - EC2 compute: ~$0.0416/hour saved (~$1/day)"
echo "   - EBS storage: Still charged (~$0.05/day)"
echo "   - Elastic IP: ⚠️ NOW charged $0.005/hour (~$0.12/day) while stopped"
echo ""
echo "📝 Note: Elastic IP (3.222.204.115) is still reserved"
echo "         Your sites will be offline until you run ./bloom-start.sh"
echo ""
echo "🌐 Sites are now OFFLINE:"
echo "   - https://bloompublic.civicapplab.com (offline)"
echo "   - https://bloomportal.civicapplab.com (offline)"
echo "   - https://bloomapi.civicapplab.com (offline)"
echo ""
