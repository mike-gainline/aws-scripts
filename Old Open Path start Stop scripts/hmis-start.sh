#!/usr/bin/env bash
# =============================================================================
# hmis-start.sh — Bring HMIS Warehouse prototype back up
#
# Starts RDS, waits for it, then scales ECS services back up.
# Total startup time: ~8-12 minutes (RDS restart is the bottleneck).
#
# Usage:  ./hmis-start.sh
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
CLUSTER="hmis-warehouse-staging"
WEB_SERVICE="hmis-web"
WORKER_SERVICE="hmis-worker"
RDS_INSTANCE="hmis-warehouse-pg"
REDIS_CLUSTER="hmis-redis"
REGION="us-east-1"
WEB_DESIRED=2
WORKER_DESIRED=1
ALB_DNS=""  # Filled in dynamically below

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }

echo ""
echo "============================================================"
echo "  HMIS Warehouse — START"
echo "============================================================"
echo ""

START_TIME=$SECONDS

# ── Step 1: Start RDS (the slowest piece — do this first) ───────────────────
log "Checking RDS instance '$RDS_INSTANCE'..."
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "not-found")

if [[ "$RDS_STATUS" == "stopped" ]]; then
  log "Starting RDS instance..."
  aws rds start-db-instance \
    --db-instance-identifier "$RDS_INSTANCE" \
    --region "$REGION" \
    --no-cli-pager > /dev/null 2>&1
  log "  ✓ RDS start initiated"
elif [[ "$RDS_STATUS" == "available" ]]; then
  log "  ✓ RDS already running"
elif [[ "$RDS_STATUS" == "starting" ]]; then
  log "  ✓ RDS already starting"
else
  err "  RDS status is '$RDS_STATUS' — may need manual intervention"
fi

# ── Step 2: Handle ElastiCache Redis ─────────────────────────────────────────
# If using Option A (delete/recreate), uncomment the block below.
# Otherwise, Redis should already be running.

REDIS_STATUS=$(aws elasticache describe-cache-clusters \
  --cache-cluster-id "$REDIS_CLUSTER" \
  --query 'CacheClusters[0].CacheClusterStatus' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "not-found")

if [[ "$REDIS_STATUS" == "available" ]]; then
  log "ElastiCache Redis: ✓ already running"
elif [[ "$REDIS_STATUS" == "not-found" ]]; then
  warn "Redis cluster not found."
  # ── OPTION A: Recreate from snapshot (uncomment if using delete/recreate) ──
  # SNAPSHOT_NAME=$(cat ~/.hmis-redis-snapshot 2>/dev/null || echo "")
  # if [[ -n "$SNAPSHOT_NAME" ]]; then
  #   log "Recreating Redis from snapshot '$SNAPSHOT_NAME'..."
  #   aws elasticache create-cache-cluster \
  #     --cache-cluster-id "$REDIS_CLUSTER" \
  #     --cache-node-type cache.t3.small \
  #     --engine redis \
  #     --engine-version 7.0 \
  #     --num-cache-nodes 1 \
  #     --cache-subnet-group-name hmis-redis-subnet-group \
  #     --security-group-ids "$REDIS_SG_ID" \
  #     --snapshot-name "$SNAPSHOT_NAME" \
  #     --region "$REGION" > /dev/null 2>&1
  #   log "  Redis recreation initiated (will wait below)"
  # else
  #   err "No snapshot name found in ~/.hmis-redis-snapshot"
  #   err "You may need to recreate Redis manually."
  # fi
  # ── END OPTION A ───────────────────────────────────────────────────────────
  warn "You may need to recreate the Redis cluster manually."
else
  info "Redis status: $REDIS_STATUS (waiting...)"
fi

# ── Step 3: Wait for RDS to become available ─────────────────────────────────
log "Waiting for RDS to become available (this takes 5-10 minutes)..."
info "  Tip: This is a good time to grab coffee."
echo ""

WAIT_START=$SECONDS
MAX_WAIT=900  # 15 minutes max

while true; do
  RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "unknown")

  ELAPSED_WAIT=$(( SECONDS - WAIT_START ))

  if [[ "$RDS_STATUS" == "available" ]]; then
    echo ""
    log "  ✓ RDS is available (took ${ELAPSED_WAIT}s)"
    break
  fi

  if [[ $ELAPSED_WAIT -ge $MAX_WAIT ]]; then
    echo ""
    err "RDS did not become available within 15 minutes."
    err "Current status: $RDS_STATUS"
    err "Check the AWS console. ECS services were NOT started."
    exit 1
  fi

  # Progress indicator (prints on the same line)
  printf "\r    Status: %-12s  Elapsed: %ds / %ds  " "$RDS_STATUS" "$ELAPSED_WAIT" "$MAX_WAIT"
  sleep 15
done

# ── Step 4: Wait for Redis (if it was being recreated) ───────────────────────
if [[ "$REDIS_STATUS" != "available" ]]; then
  log "Waiting for Redis to become available..."
  for i in $(seq 1 40); do
    REDIS_STATUS=$(aws elasticache describe-cache-clusters \
      --cache-cluster-id "$REDIS_CLUSTER" \
      --query 'CacheClusters[0].CacheClusterStatus' \
      --output text \
      --region "$REGION" 2>/dev/null || echo "not-found")
    if [[ "$REDIS_STATUS" == "available" ]]; then
      log "  ✓ Redis is available"
      break
    fi
    printf "\r    Redis status: %-12s (%d/40)  " "$REDIS_STATUS" "$i"
    sleep 15
  done
  echo ""
fi

# ── Step 5: Scale ECS services back up ───────────────────────────────────────
log "Scaling ECS web service to $WEB_DESIRED tasks..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$WEB_SERVICE" \
  --desired-count "$WEB_DESIRED" \
  --region "$REGION" \
  --no-cli-pager > /dev/null 2>&1
log "  ✓ Web service scaling to $WEB_DESIRED"

log "Scaling ECS worker service to $WORKER_DESIRED tasks..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$WORKER_SERVICE" \
  --desired-count "$WORKER_DESIRED" \
  --region "$REGION" \
  --no-cli-pager > /dev/null 2>&1
log "  ✓ Worker service scaling to $WORKER_DESIRED"

# ── Step 6: Wait for ECS tasks to reach RUNNING state ────────────────────────
log "Waiting for ECS tasks to start (1-3 minutes)..."

for i in $(seq 1 24); do
  WEB_RUNNING=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$WEB_SERVICE" \
    --query 'services[0].runningCount' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "0")
  WORKER_RUNNING=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$WORKER_SERVICE" \
    --query 'services[0].runningCount' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "0")

  if [[ "$WEB_RUNNING" -ge "$WEB_DESIRED" && "$WORKER_RUNNING" -ge "$WORKER_DESIRED" ]]; then
    log "  ✓ All tasks running (web: $WEB_RUNNING, worker: $WORKER_RUNNING)"
    break
  fi

  printf "\r    Web: %s/%s  Worker: %s/%s  (waiting 10s...)  " \
    "$WEB_RUNNING" "$WEB_DESIRED" "$WORKER_RUNNING" "$WORKER_DESIRED"
  sleep 10
done
echo ""

# ── Step 7: Check ALB health ────────────────────────────────────────────────
log "Checking ALB target health..."

# Find the ALB and target group
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names hmis-warehouse-alb \
  --query 'LoadBalancers[0].{ARN:LoadBalancerArn,DNS:DNSName}' \
  --output json \
  --region "$REGION" 2>/dev/null || echo "{}")

ALB_DNS=$(echo "$ALB_ARN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('DNS',''))" 2>/dev/null || echo "")

TG_ARN=$(aws elbv2 describe-target-groups \
  --names hmis-warehouse-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
  # Give the health check a moment
  sleep 10

  for i in $(seq 1 12); do
    HEALTH=$(aws elbv2 describe-target-health \
      --target-group-arn "$TG_ARN" \
      --query 'TargetHealthDescriptions[*].TargetHealth.State' \
      --output text \
      --region "$REGION" 2>/dev/null || echo "unknown")

    HEALTHY_COUNT=$(echo "$HEALTH" | tr '\t' '\n' | grep -c "healthy" || echo "0")

    if [[ "$HEALTHY_COUNT" -ge 1 ]]; then
      log "  ✓ $HEALTHY_COUNT healthy targets in ALB"
      break
    fi

    printf "\r    Targets: %s  (waiting for healthy, attempt %d/12)  " "$HEALTH" "$i"
    sleep 15
  done
  echo ""
else
  warn "Could not find target group — check ALB manually"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo ""
echo "============================================================"
echo "  HMIS Warehouse — RUNNING  (${MINUTES}m ${SECS}s)"
echo "============================================================"
echo ""
echo "  Services:"
echo "    • ECS web:     $WEB_DESIRED tasks"
echo "    • ECS worker:  $WORKER_DESIRED tasks"
echo "    • RDS:         available"
echo "    • Redis:       $REDIS_STATUS"
echo ""
if [[ -n "$ALB_DNS" ]]; then
  echo "  Access the app:"
  echo "    http://$ALB_DNS"
  echo ""
fi
echo "  Useful commands:"
echo "    Tail web logs:     aws logs tail $LOG_GROUP --log-stream-name-prefix web --follow"
echo "    Tail worker logs:  aws logs tail $LOG_GROUP --log-stream-name-prefix worker --follow"
echo ""
echo "  When done tonight:   ./hmis-stop.sh"
echo ""
