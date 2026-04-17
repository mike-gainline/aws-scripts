#!/usr/bin/env bash
# =============================================================================
# hmis-stop.sh — Shut down HMIS Warehouse prototype to save costs
#
# Stops ECS services, then stops RDS and ElastiCache (the expensive stuff).
# NAT Gateway and VPC are shared with SNOMass — NEVER touched.
#
# Usage:  ./hmis-stop.sh
# Time:   Completes in ~2 minutes (shutdown is fast; startup is what takes time)
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
CLUSTER="hmis-warehouse-staging"
WEB_SERVICE="hmis-web"
WORKER_SERVICE="hmis-worker"
RDS_INSTANCE="hmis-warehouse-pg"
REDIS_CLUSTER="hmis-redis"
REGION="us-east-1"
LOG_GROUP="/ecs/hmis-warehouse-staging"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; }

# ── Safety check ─────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  HMIS Warehouse — STOP (cost savings mode)"
echo "============================================================"
echo ""
echo "This will shut down:"
echo "  • ECS services (web + worker) → desired count 0"
echo "  • RDS PostgreSQL instance     → stopped"
echo "  • ElastiCache Redis cluster   → (see below)"
echo ""
echo "This will NOT touch:"
echo "  • VPC, subnets, NAT gateway"
echo "  • SNOMass MySQL RDS"
echo "  • ALB (pennies/hr when idle, keeps DNS stable)"
echo "  • S3 bucket, ECR images, Secrets Manager"
echo ""
read -p "Proceed? (y/N): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

START_TIME=$SECONDS

# ── Step 1: Scale ECS services to zero ───────────────────────────────────────
log "Scaling ECS web service to 0..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$WEB_SERVICE" \
  --desired-count 0 \
  --region "$REGION" \
  --no-cli-pager > /dev/null 2>&1 && log "  ✓ Web service scaled to 0" || warn "  Web service update failed (may already be 0)"

log "Scaling ECS worker service to 0..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$WORKER_SERVICE" \
  --desired-count 0 \
  --region "$REGION" \
  --no-cli-pager > /dev/null 2>&1 && log "  ✓ Worker service scaled to 0" || warn "  Worker service update failed (may already be 0)"

# Wait for tasks to drain (up to 60s)
log "Waiting for running tasks to drain..."
for i in $(seq 1 12); do
  RUNNING=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$WEB_SERVICE" "$WORKER_SERVICE" \
    --region "$REGION" \
    --query 'sum(services[].runningCount)' \
    --output text 2>/dev/null || echo "0")
  if [[ "$RUNNING" == "0" || "$RUNNING" == "None" ]]; then
    log "  ✓ All tasks stopped"
    break
  fi
  echo -n "    ($RUNNING tasks still running, waiting 5s...)"
  sleep 5
  echo ""
done

# ── Step 2: Stop RDS PostgreSQL ──────────────────────────────────────────────
log "Stopping RDS instance '$RDS_INSTANCE'..."
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "not-found")

if [[ "$RDS_STATUS" == "available" ]]; then
  aws rds stop-db-instance \
    --db-instance-identifier "$RDS_INSTANCE" \
    --region "$REGION" \
    --no-cli-pager > /dev/null 2>&1
  log "  ✓ RDS stop initiated (will complete in background)"
elif [[ "$RDS_STATUS" == "stopped" ]]; then
  log "  ✓ RDS already stopped"
elif [[ "$RDS_STATUS" == "stopping" ]]; then
  log "  ✓ RDS already stopping"
else
  warn "  RDS status is '$RDS_STATUS' — skipping"
fi

# ── Step 3: Handle ElastiCache Redis ─────────────────────────────────────────
# ElastiCache does NOT support stop/start like RDS. Options:
#   Option A: Delete and recreate (saves ~$25/mo, adds ~5min to startup)
#   Option B: Leave running ($0.034/hr = ~$0.82/day, but instant startup)
#
# Default: Option B (leave running) since it's cheap and simplifies startup.
# Uncomment Option A below if you want maximum savings.

log "ElastiCache Redis: leaving running (instant startup, ~\$0.82/day idle)"
# warn "ElastiCache does not support stop/start. To save the ~\$25/mo:"
# warn "  Uncomment Option A in this script to delete/recreate on each cycle."

# ── OPTION A (uncomment to enable): Delete Redis, recreate on start ──────────
# log "Creating Redis snapshot before deletion..."
# SNAPSHOT_NAME="hmis-redis-$(date +%Y%m%d-%H%M%S)"
# aws elasticache create-snapshot \
#   --cache-cluster-id "$REDIS_CLUSTER" \
#   --snapshot-name "$SNAPSHOT_NAME" \
#   --region "$REGION" > /dev/null 2>&1
# log "  Snapshot: $SNAPSHOT_NAME"
#
# log "Deleting Redis cluster..."
# aws elasticache delete-cache-cluster \
#   --cache-cluster-id "$REDIS_CLUSTER" \
#   --region "$REGION" > /dev/null 2>&1
# log "  ✓ Redis deletion initiated"
#
# # Save snapshot name for the start script
# echo "$SNAPSHOT_NAME" > ~/.hmis-redis-snapshot
# log "  Saved snapshot name to ~/.hmis-redis-snapshot"
# ── END OPTION A ─────────────────────────────────────────────────────────────

# ── Summary ──────────────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))

echo ""
echo "============================================================"
echo "  HMIS Warehouse — STOPPED  (${ELAPSED}s)"
echo "============================================================"
echo ""
echo "  Stopped/stopping:"
echo "    • ECS web + worker    → 0 tasks (Fargate billing stopped)"
echo "    • RDS PostgreSQL      → stopping (billing stops when 'stopped')"
echo ""
echo "  Still running (low cost):"
echo "    • ALB                 → ~\$0.008/hr idle"
echo "    • ElastiCache Redis   → ~\$0.034/hr"
echo "    • NAT Gateway         → shared, not our cost"
echo ""
echo "  Estimated idle cost: ~\$1.00/day (vs ~\$6.50/day running)"
echo ""
echo "  To restart:  ./hmis-start.sh"
echo ""

# ── Note on RDS auto-start ───────────────────────────────────────────────────
warn "AWS will auto-restart a stopped RDS after 7 days."
warn "If your break is longer than a week, re-run this script or"
warn "set a CloudWatch Events rule to re-stop it automatically."
