# 📑 Portfolio RDS Manager - START HERE

Welcome! This is your master index for managing RDS costs with **50-99% savings**.

---

## 🚀 Quick Start (Choose Your Path)

### Path 1: "Just Tell Me What to Do" (15 minutes)
1. Read: [`SETUP-CHECKLIST.md`](SETUP-CHECKLIST.md)
2. Run: `./deploy-portfolio-rds.sh your-email@example.com`
3. Test: `./portfolio-rds-manager.sh status`
4. Done! 🎉

### Path 2: "Explain How This Works" (30 minutes)
1. Read: [`EXECUTIVE-SUMMARY.md`](EXECUTIVE-SUMMARY.md) (5 min)
2. Read: [`README-PORTFOLIO-RDS.md`](README-PORTFOLIO-RDS.md) → Architecture section (10 min)
3. Follow: [`SETUP-CHECKLIST.md`](SETUP-CHECKLIST.md) (15 min)
4. Ready to use!

### Path 3: "I Need All the Details" (2 hours)
1. Read everything in order:
   - [`EXECUTIVE-SUMMARY.md`](EXECUTIVE-SUMMARY.md)
   - [`README-PORTFOLIO-RDS.md`](README-PORTFOLIO-RDS.md)
   - [`MANIFEST.md`](MANIFEST.md)
2. Review code: `portfolio-rds-manager.sh`, `lambda-auto-restart.py`
3. Deploy and test thoroughly

---

## 📚 Documentation Map

### 📖 By Purpose

#### "I want the big picture"
→ Start with **[`EXECUTIVE-SUMMARY.md`](EXECUTIVE-SUMMARY.md)**
- Overview of system
- Cost analysis
- Architecture diagram
- Two strategy comparison
- FAQ section

#### "I'm ready to deploy"
→ Follow **[`SETUP-CHECKLIST.md`](SETUP-CHECKLIST.md)**
- Step-by-step setup
- Verification tests
- Troubleshooting
- Next steps

#### "I need quick help"
→ Check **[`QUICK-REFERENCE.md`](QUICK-REFERENCE.md)**
- Common commands
- Troubleshooting fixes
- Cost calculator
- Emergency operations

#### "I need complete details"
→ Read **[`README-PORTFOLIO-RDS.md`](README-PORTFOLIO-RDS.md)**
- Everything about the system
- Complete command reference
- Architecture explanation
- Security best practices
- Advanced usage
- Extensive troubleshooting

#### "What exactly am I getting?"
→ See **[`MANIFEST.md`](MANIFEST.md)**
- File listing with descriptions
- What each file does
- Prerequisites
- Quality & testing info

#### "I'm lost"
→ You're here: **[`INDEX.md`](INDEX.md)** (this file)
- Navigation help
- File descriptions
- Getting unstuck

---

## 🛠️ Tools & Scripts

### 1. **Deployment Script** (`deploy-portfolio-rds.sh`)
**What**: One-command AWS infrastructure setup  
**When**: Run once during initial setup  
**Command**: `./deploy-portfolio-rds.sh your-email@example.com`  
**Creates**: CloudFormation stack, Lambda, DynamoDB, S3, SNS  
**Time**: ~5 minutes  

### 2. **CLI Tool** (`portfolio-rds-manager.sh`)
**What**: Daily command-line interface  
**When**: Every time you want to stop/start/check instances  
**Commands**:
```bash
./portfolio-rds-manager.sh status         # Check everything
./portfolio-rds-manager.sh stop <name>    # Pause instance
./portfolio-rds-manager.sh start <name>   # Resume instance
./portfolio-rds-manager.sh cost-estimate  # View costs
./portfolio-rds-manager.sh list           # List instances
```

### 3. **Configuration** (`rds-portfolio-config.yaml`)
**What**: Central configuration for all your RDS instances  
**When**: Edit when adding/removing instances  
**Location**: You keep locally, also in S3 for Lambda  

### 4. **Lambda Function** (`lambda-auto-restart.py`)
**What**: Automatic 7-day auto-restart protection  
**When**: Runs automatically every 6 hours  
**Does**: Monitors stopped instances, auto-restarts before AWS limit  
**You do**: Nothing! (fully automatic)  

### 5. **CloudFormation Template** (`portfolio-rds-cf.yaml`)
**What**: Infrastructure as code template  
**When**: Used by deploy script  
**Creates**: All AWS resources (DynamoDB, Lambda, SNS, etc.)  

---

## 🎯 Common Tasks

### Task: Deploy System (First Time)
```bash
chmod +x deploy-portfolio-rds.sh portfolio-rds-manager.sh
./deploy-portfolio-rds.sh your-email@example.com
```
→ See: [`SETUP-CHECKLIST.md`](SETUP-CHECKLIST.md) Step 2

### Task: Add New RDS Instance
```bash
# 1. Edit config
vim rds-portfolio-config.yaml
# 2. Add your instance details
# 3. Upload to S3
aws s3 cp rds-portfolio-config.yaml s3://portfolio-rds-config-<account-id>/
```
→ See: [`README-PORTFOLIO-RDS.md`](README-PORTFOLIO-RDS.md) → Configuration Reference

### Task: Stop a Database (Pause Compute)
```bash
./portfolio-rds-manager.sh stop bloom-prototype
```
→ See: [`QUICK-REFERENCE.md`](QUICK-REFERENCE.md) → Daily Commands

### Task: Start a Database
```bash
./portfolio-rds-manager.sh start bloom-prototype
```
→ See: [`QUICK-REFERENCE.md`](QUICK-REFERENCE.md) → Daily Commands

### Task: Check Current Status & Costs
```bash
./portfolio-rds-manager.sh status
./portfolio-rds-manager.sh cost-estimate
```
→ See: [`QUICK-REFERENCE.md`](QUICK-REFERENCE.md) → Common Commands

### Task: Fix a Problem
1. Check error message
2. Search: [`QUICK-REFERENCE.md`](QUICK-REFERENCE.md) → Troubleshooting
3. If not found: [`README-PORTFOLIO-RDS.md`](README-PORTFOLIO-RDS.md) → Troubleshooting

### Task: Understand How Automation Works
→ Read: [`README-PORTFOLIO-RDS.md`](README-PORTFOLIO-RDS.md) → Lambda Automation

### Task: Review Security
→ Read: [`README-PORTFOLIO-RDS.md`](README-PORTFOLIO-RDS.md) → Security Best Practices

---

## 📊 Two Strategies Explained

### Strategy 1: Stop/Start (RECOMMENDED)
- **Cost**: 50% savings (~$6.50/month for db.t3.micro)
- **Resume Time**: ~2 minutes
- **Risk**: Low (safe, instant, reversible)
- **Best For**: Databases used weekly/monthly

```bash
./portfolio-rds-manager.sh stop bloom-prototype
./portfolio-rds-manager.sh start bloom-prototype
```

### Strategy 2: Delete/Restore
- **Cost**: 98% savings (~$0.12/month for db.t3.micro)
- **Resume Time**: ~10-15 minutes
- **Risk**: Medium (requires restore)
- **Best For**: Demo databases, rarely-used projects

→ See: [`EXECUTIVE-SUMMARY.md`](EXECUTIVE-SUMMARY.md) for detailed comparison

---

## 🔍 File Organization

```
📁 Your Project Directory
├── 📄 INDEX.md                      ← You are here
├── 📄 EXECUTIVE-SUMMARY.md          ← High-level overview
├── 📄 SETUP-CHECKLIST.md            ← Step-by-step setup
├── 📄 QUICK-REFERENCE.md            ← One-page cheat sheet
├── 📄 README-PORTFOLIO-RDS.md       ← Complete reference
├── 📄 MANIFEST.md                   ← File descriptions
│
├── 🔧 SCRIPTS & CONFIG
├── 📄 portfolio-rds-manager.sh      ← CLI tool (use daily)
├── 📄 rds-portfolio-config.yaml     ← Your configuration
├── 📄 deploy-portfolio-rds.sh       ← Deployment script
├── 📄 lambda-auto-restart.py        ← Auto-restart logic
└── 📄 portfolio-rds-cf.yaml         ← Infrastructure template

📁 AWS (Created Automatically)
├── 📊 DynamoDB Table: portfolio-rds-state
├── 🪣 S3: portfolio-rds-config-<id>
├── 🪣 S3: portfolio-db-backups-<id>
├── 📨 SNS: portfolio-rds-notifications
├── ⚡ Lambda: portfolio-rds-manager
├── 📅 EventBridge: portfolio-rds-auto-restart-schedule
└── 🔐 IAM Role: portfolio-rds-lambda-role
```

---

## ❓ Need Help?

### Q: "Where do I start?"
→ **[SETUP-CHECKLIST.md](SETUP-CHECKLIST.md)** (follow step by step)

### Q: "How do I use it?"
→ **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** (copy-paste commands)

### Q: "Why isn't it working?"
→ **[README-PORTFOLIO-RDS.md](README-PORTFOLIO-RDS.md)** → Troubleshooting

### Q: "How much will I save?"
→ **[EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md)** → Cost Analysis

### Q: "What if I want all the details?"
→ **[README-PORTFOLIO-RDS.md](README-PORTFOLIO-RDS.md)** (comprehensive guide)

### Q: "What exactly am I getting?"
→ **[MANIFEST.md](MANIFEST.md)** (file descriptions)

---

## ⏱️ Time Estimates

| Task | Time | Document |
|------|------|----------|
| Read overview | 5 min | EXECUTIVE-SUMMARY.md |
| Initial setup | 10 min | SETUP-CHECKLIST.md |
| First deployment | 5 min | deploy-portfolio-rds.sh |
| Configure instances | 5 min | rds-portfolio-config.yaml |
| First stop/start test | 5 min | QUICK-REFERENCE.md |
| **Total setup** | **30 min** | Follow SETUP-CHECKLIST.md |

| Task | Frequency | Document |
|------|-----------|----------|
| Check status | Weekly | QUICK-REFERENCE.md |
| Review costs | Monthly | portfolio-rds-manager.sh |
| Monitor logs | Monthly | README-PORTFOLIO-RDS.md |

---

## 🎯 Success Criteria

After setup, you'll have:

✅ CloudFormation stack deployed  
✅ DynamoDB tracking stopped instances  
✅ Lambda auto-restart protection  
✅ SNS email notifications working  
✅ CLI tool ready for manual control  
✅ Configuration synced to S3  
✅ Cost tracking enabled  

---

## 💰 Expected Savings

**Example: 2 db.t3.micro instances**

| Strategy | Monthly | Annual |
|----------|---------|--------|
| All running | $26.00 | $312.00 |
| Stop half the time | $13.00 | $156.00 |
| **Annual savings** | — | **$156** |

For delete-restore: **$309 saved annually** (99%)

---

## 🔗 Quick Links

**Getting Started**
- [EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md) - Overview
- [SETUP-CHECKLIST.md](SETUP-CHECKLIST.md) - Step-by-step
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Commands

**Complete Reference**
- [README-PORTFOLIO-RDS.md](README-PORTFOLIO-RDS.md) - Everything
- [MANIFEST.md](MANIFEST.md) - File descriptions

**Tools**
- `portfolio-rds-manager.sh` - CLI tool
- `deploy-portfolio-rds.sh` - Setup script
- `rds-portfolio-config.yaml` - Configuration

---

## 🚀 Next Step

Choose your path above and get started! 

**Recommended**: Click on [**SETUP-CHECKLIST.md**](SETUP-CHECKLIST.md) →

---

## 📞 Support

- **Questions during setup?** → See [SETUP-CHECKLIST.md](SETUP-CHECKLIST.md) → Troubleshooting
- **How to use commands?** → See [QUICK-REFERENCE.md](QUICK-REFERENCE.md)
- **Something broke?** → See [README-PORTFOLIO-RDS.md](README-PORTFOLIO-RDS.md) → Troubleshooting
- **Want all details?** → See [README-PORTFOLIO-RDS.md](README-PORTFOLIO-RDS.md)

---

**Version**: 1.0  
**Status**: Production Ready  
**Last Updated**: March 2026  

**Ready to save 50-99% on database costs?** Let's go! 🎉
