# Using Claude Code to Deploy Portfolio RDS Manager

## Overview

Claude Code is a command-line tool that lets you delegate coding/automation tasks to Claude. You can use it to:
- Deploy the CloudFormation infrastructure
- Upload configuration to S3
- Create necessary IAM policies
- Run all setup steps automatically

This guide shows you exactly how to set it up and what prompts to use.

---

## Prerequisites

### 1. Install Claude Code

```bash
# Install Claude Code CLI tool
npm install -g @anthropic-ai/claude-code

# Or if using a specific version
npm install -g @anthropic-ai/claude-code@latest

# Verify installation
claude-code --version
```

### 2. Set Your API Key

```bash
export ANTHROPIC_API_KEY="your-api-key-here"

# Or add to ~/.bashrc or ~/.zshrc for permanence
echo 'export ANTHROPIC_API_KEY="your-api-key-here"' >> ~/.bashrc
source ~/.bashrc
```

Get your API key from: https://console.anthropic.com/account/keys

### 3. Configure AWS Credentials

```bash
# Install AWS CLI if needed
brew install awscli

# Configure credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
```

### 4. Have Files Ready

Download all 12 files from the Portfolio RDS Manager into a project directory:

```bash
mkdir ~/portfolio-rds-manager
cd ~/portfolio-rds-manager
# Copy all 12 files here
```

---

## Method 1: Simple One-Command Deployment (Recommended)

This is the easiest way - give Claude Code one comprehensive prompt and let it do everything.

### Step 1: Create a Prompt File

Create `claude-code-prompt.txt`:

```
I need you to deploy the Portfolio RDS Manager system to AWS.

Here's what to do:

PREREQUISITES:
- AWS CLI is configured with credentials
- I have all the necessary files in this directory
- My AWS account ID is: 311330778203
- I want notifications sent to: your-email@example.com

DEPLOYMENT STEPS:

1. **Verify Setup**
   - Check AWS CLI is configured: aws sts get-caller-identity
   - Check all required files exist: portfolio-rds-cf.yaml, deploy-portfolio-rds.sh, etc.
   - List files to verify

2. **Make Scripts Executable**
   - chmod +x deploy-portfolio-rds.sh
   - chmod +x portfolio-rds-manager.sh
   - chmod +x lambda-auto-restart.py (or verify it's executable)

3. **Update Configuration**
   - Read rds-portfolio-config.yaml
   - Update the account ID from 311330778203 to the actual account (get from aws sts)
   - Update S3 bucket names with correct account ID
   - Keep the default instance names (bloom-prototype, snomass) - user will customize later
   - Save updated config

4. **Deploy Infrastructure**
   - Run: ./deploy-portfolio-rds.sh your-email@example.com
   - Wait for CloudFormation stack to complete
   - Verify all resources were created

5. **Verify Deployment**
   - aws cloudformation describe-stacks --stack-name portfolio-rds-manager
   - aws dynamodb describe-table --table-name portfolio-rds-state
   - aws lambda get-function --function-name portfolio-rds-manager
   - aws events describe-rule --name portfolio-rds-auto-restart-schedule

6. **Summary**
   - Report what was created
   - Provide the S3 bucket names (config and backups)
   - Show Lambda function ARN
   - Show DynamoDB table name

IMPORTANT:
- Make all operations verbose (show what's happening)
- Stop and report if any step fails
- Ask for clarification before making assumptions
- Keep the original files safe (don't delete them)
```

### Step 2: Run Claude Code

```bash
cd ~/portfolio-rds-manager

# Run with the prompt file
claude-code claude-code-prompt.txt

# Or run interactively (paste prompt at the >)
claude-code
> [paste the prompt above]
```

### Step 3: Monitor Progress

Claude Code will:
- Execute each bash command
- Show you the output
- Ask questions if it needs clarification
- Report back when complete

---

## Method 2: Step-by-Step Prompts (More Control)

If you want to control each step, use multiple prompts:

### Prompt 1: Verify & Setup

```
I'm deploying the Portfolio RDS Manager. 

First, please:
1. Verify AWS CLI is configured: aws sts get-caller-identity
2. List all files in this directory
3. Make these scripts executable:
   - deploy-portfolio-rds.sh
   - portfolio-rds-manager.sh
4. Show me the AWS account ID

Don't make any changes yet, just report what you find.
```

### Prompt 2: Update Configuration

```
Now please update the configuration:

1. Read rds-portfolio-config.yaml
2. Replace all instances of "311330778203" with the actual account ID from AWS
3. Replace all instances of "your-email@example.com" with: YOUR-EMAIL@EXAMPLE.COM
4. Save the updated file
5. Show me the updated instances section
```

### Prompt 3: Deploy Infrastructure

```
Now deploy the infrastructure:

1. Run: ./deploy-portfolio-rds.sh YOUR-EMAIL@EXAMPLE.COM
2. Wait for the CloudFormation stack to complete (it will take 3-5 minutes)
3. When done, run these verification commands:
   - aws cloudformation describe-stacks --stack-name portfolio-rds-manager --query 'Stacks[0].StackStatus'
   - aws s3 ls | grep portfolio
   - aws dynamodb list-tables | grep portfolio
4. Report the results

If anything fails, stop and tell me what went wrong.
```

### Prompt 4: Final Verification

```
Verify the deployment is complete:

1. Get the S3 config bucket name
2. Upload the updated rds-portfolio-config.yaml to that bucket
3. Verify the Lambda function was deployed
4. Check that DynamoDB table exists
5. Verify SNS topic was created

Report all bucket names, Lambda ARN, and status.
```

---

## Method 3: Fully Automated (No Human Interaction)

For completely hands-off deployment:

Create `deploy.sh`:

```bash
#!/bin/bash

# Make scripts executable
chmod +x deploy-portfolio-rds.sh portfolio-rds-manager.sh

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Update config with actual account ID
sed -i "s/311330778203/$AWS_ACCOUNT_ID/g" rds-portfolio-config.yaml
sed -i "s/portfolio-db-backups-[0-9]*/portfolio-db-backups-$AWS_ACCOUNT_ID/g" rds-portfolio-config.yaml
sed -i "s/portfolio-rds-config-[0-9]*/portfolio-rds-config-$AWS_ACCOUNT_ID/g" rds-portfolio-config.yaml

echo "Configuration updated"

# Deploy with Claude Code
claude-code << 'EOF'
The portfolio RDS manager files are ready. 

Please run: ./deploy-portfolio-rds.sh your-email@example.com

Wait for it to complete, then verify:
1. CloudFormation stack status
2. S3 buckets created
3. Lambda function deployed
4. DynamoDB table exists

Report completion status.
EOF
```

Then run:
```bash
chmod +x deploy.sh
./deploy.sh
```

---

## Complete Prompt (All-in-One)

If you want to give Claude Code one comprehensive prompt that does everything:

```
PORTFOLIO RDS MANAGER DEPLOYMENT

I need you to deploy the Portfolio RDS Manager system to AWS.

CONTEXT:
- This is a cost-optimization system for AWS RDS instances
- Files are in this directory: deploy-portfolio-rds.sh, portfolio-rds-manager.sh, etc.
- AWS CLI is configured with valid credentials
- Email for notifications: your-email@example.com

DEPLOYMENT WORKFLOW:

1. **Pre-flight Checks**
   - Run: aws sts get-caller-identity
   - Get AWS Account ID from output
   - List files: ls -la *.sh *.yaml *.py *.md
   - Verify all required files exist

2. **Prepare Files**
   - Make executable: chmod +x deploy-portfolio-rds.sh portfolio-rds-manager.sh
   - Read rds-portfolio-config.yaml
   - Replace account ID 311330778203 with actual account ID
   - Replace "your-email@example.com" with: your-email@example.com
   - Save updated config

3. **Deploy Infrastructure**
   - Run: ./deploy-portfolio-rds.sh your-email@example.com
   - This takes 3-5 minutes
   - Wait for CloudFormation to complete
   - Save all output

4. **Verify Each Component**
   - DynamoDB: aws dynamodb describe-table --table-name portfolio-rds-state
   - S3 buckets: aws s3 ls | grep portfolio
   - Lambda: aws lambda get-function --function-name portfolio-rds-manager
   - EventBridge: aws events describe-rule --name portfolio-rds-auto-restart-schedule
   - SNS: aws sns list-topics | grep portfolio

5. **Upload Configuration**
   - Get S3 config bucket name from stack outputs
   - Upload config: aws s3 cp rds-portfolio-config.yaml s3://portfolio-rds-config-<ACCOUNT_ID>/

6. **Final Report**
   - Summarize what was created
   - List resource names and ARNs
   - Confirm everything is ready to use
   - Next steps for the user

IMPORTANT:
- Show all command outputs
- Stop immediately if any command fails
- Ask before making assumptions
- Keep original files intact
- Make this verbose so we can see progress

Ready? Proceed with step 1.
```

---

## Useful Claude Code Commands

```bash
# Run Claude Code interactively
claude-code

# Run with a prompt file
claude-code my-prompt.txt

# Run a specific command through Claude Code
claude-code --exec "aws sts get-caller-identity"

# Get Claude Code help
claude-code --help

# Check Claude Code version
claude-code --version
```

---

## What Claude Code Can & Can't Do

### ✅ Claude Code CAN:
- Run bash commands
- Execute AWS CLI commands
- Read/write files
- Create directories
- Run Python scripts
- Edit configuration files
- Deploy CloudFormation stacks
- Wait for processes to complete
- Parse JSON/YAML output

### ❌ Claude Code CANNOT:
- Interact with graphical UIs
- Make payments or account changes beyond CLI
- Access your AWS console directly (uses CLI only)
- Store persistent state between sessions
- Run truly interactive prompts (no manual CLI input during execution)

---

## Troubleshooting Claude Code Deployment

### Issue: "aws: command not found"
**Solution**: Install AWS CLI
```bash
brew install awscli
aws configure
```

### Issue: "Permission denied" on scripts
**Solution**: Make them executable first
```bash
chmod +x *.sh
```

### Issue: CloudFormation stack creation fails
**Solution**: Check the error message and use this prompt:
```
The CloudFormation stack failed to create. 

Please:
1. Run: aws cloudformation describe-stacks --stack-name portfolio-rds-manager
2. Look for the StatusReason field
3. Tell me what the error was
4. Suggest fixes
```

### Issue: "Invalid API Key"
**Solution**: Set your API key correctly
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
claude-code --version  # Test it works
```

### Issue: Script doesn't complete
**Solution**: Break it into smaller prompts (Method 2 above)

---

## Recommended Approach

**Start with Method 1 (One Comprehensive Prompt):**

1. Prepare your environment (AWS CLI, Claude Code installed, files downloaded)
2. Create the comprehensive prompt above
3. Run: `claude-code complete-prompt.txt`
4. Let it run to completion
5. Review the output
6. If it fails, use Method 2 to troubleshoot step-by-step

---

## After Deployment

Once Claude Code completes deployment:

```bash
# Test the CLI tool
./portfolio-rds-manager.sh status

# Check Lambda logs
aws logs tail /aws/lambda/portfolio-rds-manager --follow

# Verify DynamoDB
aws dynamodb scan --table-name portfolio-rds-state

# View cost estimates
./portfolio-rds-manager.sh cost-estimate
```

---

## Example Session

Here's what a typical Claude Code session looks like:

```
$ claude-code
> [paste your comprehensive prompt]

Claude Code executing...

Step 1: Pre-flight checks
$ aws sts get-caller-identity
{
  "UserId": "AIDAI...",
  "Account": "311330778203",
  "Arn": "arn:aws:iam::311330778203:user/your-user"
}
✓ AWS configured, Account ID: 311330778203

$ ls -la *.sh *.yaml *.py
-rwxr-xr-x  12140 deploy-portfolio-rds.sh
-rwxr-xr-x  15300 portfolio-rds-manager.sh
... (more files)
✓ All files present

Step 2: Prepare files
Updating configuration with account ID 311330778203...
✓ Configuration updated

Step 3: Deploy infrastructure
$ ./deploy-portfolio-rds.sh your-email@example.com

Starting deployment...
Deploying CloudFormation stack portfolio-rds-manager...
Waiting for stack creation... (this takes 3-5 minutes)
✓ Stack created successfully

Step 4: Verify components
$ aws dynamodb describe-table --table-name portfolio-rds-state
✓ DynamoDB table exists and is active

$ aws s3 ls | grep portfolio
2026-03-13 14:32:45 portfolio-rds-config-311330778203
2026-03-13 14:32:45 portfolio-db-backups-311330778203
✓ S3 buckets created

$ aws lambda get-function --function-name portfolio-rds-manager
✓ Lambda function deployed and ready

Step 5: Upload configuration
$ aws s3 cp rds-portfolio-config.yaml s3://portfolio-rds-config-311330778203/
✓ Configuration uploaded to S3

Step 6: Final Report
═══════════════════════════════════════════════════════════
✅ DEPLOYMENT COMPLETE

Created Resources:
- DynamoDB Table: portfolio-rds-state
- S3 Config Bucket: portfolio-rds-config-311330778203
- S3 Backup Bucket: portfolio-db-backups-311330778203
- Lambda Function: portfolio-rds-manager
- EventBridge Rule: portfolio-rds-auto-restart-schedule
- SNS Topic: portfolio-rds-notifications
- IAM Role: portfolio-rds-lambda-role

Next Steps:
1. Update rds-portfolio-config.yaml with your RDS instance details
2. Test with: ./portfolio-rds-manager.sh status
3. Stop an instance: ./portfolio-rds-manager.sh stop bloom-prototype

═══════════════════════════════════════════════════════════
```

---

## Summary

**Best Practice: Use Claude Code for Deployment**

1. Install Claude Code and configure API key
2. Download all 12 files to a directory
3. Use the comprehensive prompt above (or Method 1)
4. Let Claude Code handle the entire deployment
5. Verify with the post-deployment commands
6. You're done! Infrastructure is live and ready to use

This way, Claude (the AI) does all the work - you just provide the files and prompt!

---

## Next: After Deployment

Once deployed, use the CLI tool daily:

```bash
# Check status
./portfolio-rds-manager.sh status

# Stop an instance (pause compute)
./portfolio-rds-manager.sh stop bloom-prototype

# Start it again
./portfolio-rds-manager.sh start bloom-prototype

# View cost estimates
./portfolio-rds-manager.sh cost-estimate
```

The Lambda function runs automatically every 6 hours. You don't need to do anything else!

---

**Questions about Claude Code?**  
https://docs.anthropic.com/claude-code/overview

**Need help with deployment?**  
Check SETUP-CHECKLIST.md or README-PORTFOLIO-RDS.md
