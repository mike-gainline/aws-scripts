# NAT Gateway Manager - Quick Start

## 3-Step Setup with Claude Code

### Step 1: Download NAT Manager Files

You need 3 files for the NAT Manager (in same directory as RDS Manager):

```
~/Code/GitHub/portfolio-rds-manager/
├── portfolio-nat-manager.sh      ← CLI tool
├── nat-portfolio-config.yaml     ← Configuration
└── CLAUDE-CODE-NAT-PROMPT.txt   ← Setup prompt
```

Plus documentation:
- `README-NAT-GATEWAY-MANAGER.md` (reference)

### Step 2: Run Claude Code Setup

```bash
cd ~/Code/GitHub/portfolio-rds-manager
claude-code

# Paste entire contents of CLAUDE-CODE-NAT-PROMPT.txt
# Let it run (discovers your NAT Gateways, configures everything)
```

**What Claude Code does**:
- ✅ Finds your existing NAT Gateways in AWS
- ✅ Captures subnet IDs, Elastic IPs, route tables
- ✅ Updates nat-portfolio-config.yaml automatically
- ✅ Tests that everything works
- ✅ Shows you how to use it

### Step 3: Start Using It

```bash
./portfolio-nat-manager.sh status            # See current state
./portfolio-nat-manager.sh stop primary-nat  # Delete NAT (save money)
./portfolio-nat-manager.sh start primary-nat # Recreate NAT
./portfolio-nat-manager.sh cost-estimate     # View potential savings
```

---

## What It Does

### Stop (Delete NAT Gateway)
```bash
./portfolio-nat-manager.sh stop primary-nat
```
- Deletes NAT Gateway (~30 seconds)
- Preserves Elastic IP
- **Saves ~$40/month immediately**
- Private subnets lose outbound internet

### Start (Recreate NAT Gateway)
```bash
./portfolio-nat-manager.sh start primary-nat
```
- Recreates NAT Gateway (2-3 minutes)
- Uses same Elastic IP
- Updates route tables automatically
- **Cost resumes to ~$40/month**

---

## Cost Savings

**For prototyping**, if you use NAT 25% of the time:

| Component | Cost |
|-----------|------|
| **Running full month** | $40/month |
| **Running 25% of time** | $10/month |
| **Savings** | **$30/month** |

**Annual savings: $360/year** for just one NAT Gateway!

Combined with RDS manager: **$600-800/year**

---

## Quick Commands

```bash
# Check what NAT Gateways are configured
./portfolio-nat-manager.sh list

# See current status and costs
./portfolio-nat-manager.sh status

# Delete NAT (save money)
./portfolio-nat-manager.sh stop <name>

# Recreate NAT (when you need it)
./portfolio-nat-manager.sh start <name>

# View cost breakdown
./portfolio-nat-manager.sh cost-estimate
```

---

## Typical Workflow

### During Development
```bash
# Morning: Start NAT
./portfolio-nat-manager.sh start primary-nat
# Wait 2-3 minutes for it to be ready
# Develop and test normally

# Evening: Stop NAT
./portfolio-nat-manager.sh stop primary-nat
# Immediately saves $40/month
```

### For a Demo
```bash
# Before demo
./portfolio-nat-manager.sh start primary-nat

# Demo goes great, everything works

# After demo
./portfolio-nat-manager.sh stop primary-nat
```

---

## Integration with RDS Manager

Use both managers together for maximum savings:

```bash
# Stop everything
./portfolio-nat-manager.sh stop primary-nat
./portfolio-rds-manager.sh stop bloom-prototype
./portfolio-rds-manager.sh stop snomass

# Check combined costs
./portfolio-nat-manager.sh cost-estimate
./portfolio-rds-manager.sh cost-estimate

# Start it all again when needed
./portfolio-nat-manager.sh start primary-nat
./portfolio-rds-manager.sh start bloom-prototype
./portfolio-rds-manager.sh start snomass
```

---

## Important Notes

❌ **NAT Gateways can't be paused** (unlike RDS)
- They must be deleted to stop charges
- Takes ~30 seconds to delete

✅ **Elastic IPs are preserved**
- Your EIP address stays safe
- Reused when you recreate the NAT

✅ **Route tables updated automatically**
- No manual routing configuration needed
- Everything happens automatically

⏱️ **Recreating takes 2-3 minutes**
- Longer than stopping, but still quick
- Good for "I need internet access again" moments

---

## Files Explained

| File | Purpose |
|------|---------|
| `portfolio-nat-manager.sh` | CLI tool (use this daily) |
| `nat-portfolio-config.yaml` | Configuration (Claude Code sets this up) |
| `CLAUDE-CODE-NAT-PROMPT.txt` | Setup prompt (paste into Claude Code) |
| `README-NAT-GATEWAY-MANAGER.md` | Full documentation (reference) |

---

## Troubleshooting Quick Tips

**"NAT Gateway not found"**
- Check the name matches: `./portfolio-nat-manager.sh list`

**"Timeout waiting for NAT"**
- Wait a moment, AWS is slow sometimes. Try again.

**"Failed to delete"**
- Wait 30 seconds: `sleep 30` then try again

**Need more help?**
- See `README-NAT-GATEWAY-MANAGER.md` → Troubleshooting

---

## Next Steps

1. Download the 3 NAT Manager files
2. Run `claude-code` with the NAT prompt
3. Wait for setup to complete
4. Run: `./portfolio-nat-manager.sh status`
5. Start saving money!

**Total setup time**: ~10 minutes (mostly automated by Claude Code)

---

## Expected Results After Setup

```
$ ./portfolio-nat-manager.sh status

ℹ Portfolio NAT Gateway Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Running
    Name:     primary-nat
    Status:   available
    Cost:     ~$40/month

  ✓ Deleted
    Name:     backup-nat
    Status:   deleted
    Cost:     ~$0.32/month

💰 Cost Summary
  Running:  $40/month
  Deleted:  $0/month
  Total:    $40/month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Simple, clean, and you're saving money! 🎉

---

**Ready?** Follow the 3-step setup above!
