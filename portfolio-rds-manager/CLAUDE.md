# Portfolio RDS & NAT Manager - Claude Code Context

## Project Purpose

Cost-optimization tooling for AWS prototyping environments. Two managers work together:
- **RDS Manager** — stop/start RDS instances to save ~50% monthly
- **NAT Manager** — delete/recreate NAT Gateways to save ~$40/month each

## ⚠ Keep This Repo Private

The YAML config files (`nat-portfolio-config.yaml`, `rds-portfolio-config.yaml`) contain
account-specific AWS resource IDs: account ID, subnet IDs, security group IDs, EIP
allocation IDs, and route table IDs. These are gitignored — the committed versions are
`*.example.yaml` with placeholders.

**If you ever consider making this repo public:** verify `git status` shows the real
config files as untracked/ignored, not committed.

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
- **Bloom Housing Prototype** — RDS (orchestrated via `bloom-deploy/bloom-up.sh` and `bloom-down.sh`)

## Finding AWS Resource IDs (for config setup)

```bash
# Get subnet IDs
aws ec2 describe-subnets --query 'Subnets[].{Name:Tags[0].Value,SubnetId:SubnetId}' --output table --profile housing-prototype

# Get Elastic IP allocation IDs
aws ec2 describe-addresses --domain vpc --profile housing-prototype

# Get route table IDs
aws ec2 describe-route-tables --query 'RouteTables[].{Name:Tags[0].Value,RouteTableId:RouteTableId}' --output table --profile housing-prototype
```

## NAT State File Format

`.portfolio-nat-state.json` tracks each gateway:

```json
{
  "portfolio-managed-nat": {
    "nat_gateway_id": "ngw-xxxxxxxx",
    "elastic_ip_allocation_id": "eipalloc-xxxxxxxx",
    "status": "available",
    "public_ip": "52.72.164.240",
    "last_action": "Created at 2026-03-13T14:30:00Z"
  }
}
```

If this file is missing or stale, `stop` auto-syncs by querying AWS via Name tag.

## Troubleshooting

**"Unable to locate credentials"** → Run `aws sso login --profile housing-prototype`

**"NAT Gateway already deleted" when it's actually running** → State file is stale. The `stop` command now handles this automatically by syncing state and looking up by Name tag.

**"NAT Gateway not found: <name>"** → Name doesn't match config. Run `./portfolio-nat-manager.sh list` to see configured names.

**"Timeout waiting for NAT Gateway"** → AWS is slow. Wait 30 seconds and retry the same command.

**Route table updates fail** → Non-fatal. NAT was created/deleted but route update failed. Update manually:
```bash
aws ec2 replace-route --route-table-id <rtb-id> --destination-cidr-block 0.0.0.0/0 --nat-gateway-id <new-nat-id> --profile housing-prototype
```

**"Elastic IP not configured"** → State file missing the allocation ID. Get it and patch the state file:
```bash
aws ec2 describe-addresses --domain vpc --profile housing-prototype
# Then edit .portfolio-nat-state.json and add the elastic_ip_allocation_id field
```
