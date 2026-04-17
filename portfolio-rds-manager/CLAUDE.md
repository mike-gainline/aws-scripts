# Portfolio RDS & NAT Manager - Claude Code Context

## Project Purpose

Cost-optimization tooling for AWS prototyping environments. Two managers work together:
- **RDS Manager** — stop/start RDS instances to save ~50% monthly
- **NAT Manager** — delete/recreate NAT Gateways to save ~$40/month each

## AWS Configuration

- **Region**: `us-east-1`
- **AWS CLI Profile**: `housing-prototype` (SSO)
- **Account**: SSO-based — must refresh before running scripts

```bash
# Refresh SSO session before using any AWS scripts
aws sso login --profile housing-prototype
```

All scripts use `AWS_PROFILE=housing-prototype`. This is set inside `portfolio-nat-manager.sh` via:
```bash
AWS_PROFILE="${AWS_PROFILE:-housing-prototype}"
```

Override at runtime if needed: `AWS_PROFILE=other-profile ./portfolio-nat-manager.sh ...`

## Key Files

| File | Purpose |
|------|---------|
| `portfolio-nat-manager.sh` | NAT Gateway lifecycle CLI (stop/start/status) |
| `nat-portfolio-config.yaml` | NAT Gateway config (subnet, EIP, route tables) |
| `.portfolio-nat-state.json` | Local state file — tracks NAT IDs and status |
| `portfolio-rds-manager.sh` | RDS instance lifecycle CLI |
| `rds-portfolio-config.yaml` | RDS instance configuration |
| `deploy-portfolio-rds.sh` | One-time CloudFormation deployment script |
| `lambda-auto-restart.py` | Lambda for 7-day auto-restart protection |
| `portfolio-rds-cf.yaml` | CloudFormation template |

## NAT Manager — Known Behaviors & Fixes

### State File Sync
The state file (`.portfolio-nat-state.json`) can become stale if a NAT gateway is deleted outside the script. The `stop` command now auto-syncs state when it detects this condition.

### Stale ID Handling
If the saved `nat_gateway_id` no longer exists in AWS (wrong/old ID), `stop` falls through to a Name-tag lookup to find the real active gateway before proceeding.

### Silent Auth Failures
AWS CLI errors were being silenced (`2>/dev/null || echo "deleted"`), causing auth failures to look like deleted gateways. Fixed by adding `--profile` to all AWS calls — errors now correctly surface as auth issues rather than false "deleted" status.

## Common Commands

```bash
# NAT Gateway
./portfolio-nat-manager.sh status
./portfolio-nat-manager.sh stop portfolio-managed-nat
./portfolio-nat-manager.sh start portfolio-managed-nat
./portfolio-nat-manager.sh cost-estimate

# RDS
./portfolio-rds-manager.sh status
./portfolio-rds-manager.sh stop bloom-prototype
./portfolio-rds-manager.sh start bloom-prototype

# Stop everything (max savings)
./portfolio-nat-manager.sh stop portfolio-managed-nat
./portfolio-rds-manager.sh stop bloom-prototype
./portfolio-rds-manager.sh stop snomass
```

## Applications Using This Infrastructure

- **SNOMass Portal** — RDS, Lambda API, Lambda Migration
- **Bloom Housing Prototype** — RDS

## Troubleshooting

**"Unable to locate credentials"** → Run `aws sso login --profile housing-prototype`

**"NAT Gateway already deleted" when it's actually running** → State file is stale. The `stop` command now handles this automatically by syncing state and looking up by Name tag.

**Route table updates fail** → Non-fatal. NAT was created/deleted but route update failed. Update manually:
```bash
aws ec2 replace-route --route-table-id <rtb-id> --destination-cidr-block 0.0.0.0/0 --nat-gateway-id <new-nat-id> --profile housing-prototype
```
