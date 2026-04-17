# ⚡ Quick Start - You Already Have Claude Code Ready!

Since you already have Claude Code installed and working with AWS, here's your actual workflow:

---

## 3-Step Deployment

### Step 1: Download Files to Your Project (2 minutes)

```bash
# Go to your GitHub code area
cd ~/Code/GitHub

# Create the project folder
mkdir portfolio-rds-manager
cd portfolio-rds-manager

# Download all files from /mnt/user-data/outputs/
# (Use the file browser below, or copy-paste the contents)
```

**Files you need** (all 14 are in the file browser):
- All *.sh files (3)
- All *.yaml files (2) 
- All *.py files (1)
- All *.md files (8)

### Step 2: Copy the Deployment Prompt (1 minute)

```bash
# Copy everything from CLAUDE-CODE-PROMPT.txt
# This is what you'll paste into Claude Code
```

### Step 3: Run Claude Code (15 minutes, mostly waiting)

```bash
claude-code

# At the prompt (>), paste the contents of CLAUDE-CODE-PROMPT.txt
# Replace: YOUR-EMAIL@EXAMPLE.COM with your actual email
# Hit Enter and let it run
```

---

## That's It! 

Your infrastructure will be deployed automatically:
- ✅ CloudFormation stack
- ✅ Lambda function
- ✅ DynamoDB table
- ✅ S3 buckets
- ✅ SNS notifications
- ✅ EventBridge automation

---

## Use It Immediately After

```bash
cd ~/Code/GitHub/portfolio-rds-manager

# Check status
./portfolio-rds-manager.sh status

# Stop an instance (pause compute, save money)
./portfolio-rds-manager.sh stop bloom-prototype

# Start it again
./portfolio-rds-manager.sh start bloom-prototype

# View cost estimates
./portfolio-rds-manager.sh cost-estimate
```

---

## Important Notes

✅ **You don't need to**:
- Install Claude Code (you have it)
- Set up API keys (you have them)
- Configure AWS (you have it)
- Change the prompt (use as-is)

✅ **Just change**:
- Replace `YOUR-EMAIL@EXAMPLE.COM` with your actual email in the prompt

✅ **Everything else**:
- Works exactly as-is with your existing setup

---

## The Prompt to Copy

See file: **CLAUDE-CODE-PROMPT.txt**

That's the one to copy. Just replace your email and paste into Claude Code.

---

## Questions?

- **"Where's the /mnt directory?"** → It's where I stored the files. Just download them from the file browser.
- **"Do I need new API keys?"** → No, use what you have.
- **"Will the prompt work?"** → Yes, exactly as-is.
- **"How long does deployment take?"** → About 15 minutes (5-10 minutes for CloudFormation, rest is verification).

---

## Success Looks Like This

When Claude Code finishes, you'll see:

```
✅ DEPLOYMENT COMPLETE

AWS Resources Created:
  ├─ CloudFormation Stack: portfolio-rds-manager
  ├─ DynamoDB Table: portfolio-rds-state
  ├─ S3 Config Bucket: portfolio-rds-config-311330778203
  ├─ S3 Backup Bucket: portfolio-db-backups-311330778203
  ├─ Lambda Function: portfolio-rds-manager
  ├─ EventBridge Rule: portfolio-rds-auto-restart-schedule
  ├─ SNS Topic: portfolio-rds-notifications
  └─ IAM Role: portfolio-rds-lambda-role

🎯 NEXT STEPS:
1. ./portfolio-rds-manager.sh status
2. Edit rds-portfolio-config.yaml with your RDS details
3. ./portfolio-rds-manager.sh stop <instance-name>
```

---

## One More Thing

After Claude Code finishes, you need to update the config with your actual RDS instance IDs:

```bash
# Edit this file
vim rds-portfolio-config.yaml

# Change:
# - name: "bloom-prototype"
#   db_identifier: "bloom-prototype-db"  ← Your actual RDS identifier
# - name: "snomass"  
#   db_identifier: "snomassdatabasestack-..."  ← Your actual RDS identifier
# And update security group IDs

# Upload updated config
aws s3 cp rds-portfolio-config.yaml s3://portfolio-rds-config-311330778203/
```

But everything else is done! ✅

---

**Ready?** 

1. Download files (from browser below)
2. Copy prompt from CLAUDE-CODE-PROMPT.txt
3. Run `claude-code` and paste
4. Wait 15 minutes
5. Start saving money! 🎉

---

**File browser below shows all 15 files you need.**

Just click and download each one to `~/Code/GitHub/portfolio-rds-manager/`
