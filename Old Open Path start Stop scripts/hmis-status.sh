#!/usr/bin/env bash
# =============================================================================
# hmis-status.sh — Quick status check for all HMIS Warehouse components
#
# Usage:  ./hmis-status.sh
# =============================================================================

set -euo pipefail

CLUSTER="hmis-warehouse-staging"
RDS_INSTANCE="hmis-warehouse-pg"
REDIS_CLUSTER="hmis-redis"
REGION="us-east-1"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "============================================================"
echo "  HMIS Warehouse — Status Check"
echo "  $(date)"
echo "============================================================"
echo ""

# ── RDS ──────────────────────────────────────────────────────────────────────
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "not-found")

case "$RDS_STATUS" in
  available) COLOR=$GREEN ;;
  stopped)   COLOR=$YELLOW ;;
  *)         COLOR=$RED ;;
esac
echo -e "  RDS PostgreSQL:    ${COLOR}${RDS_STATUS}${NC}"

# ── ElastiCache ──────────────────────────────────────────────────────────────
REDIS_STATUS=$(aws elasticache describe-cache-clusters \
  --cache-cluster-id "$REDIS_CLUSTER" \
  --query 'CacheClusters[0].CacheClusterStatus' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "not-found")

case "$REDIS_STATUS" in
  available) COLOR=$GREEN ;;
  *)         COLOR=$RED ;;
esac
echo -e "  ElastiCache Redis: ${COLOR}${REDIS_STATUS}${NC}"

# ── ECS Services ─────────────────────────────────────────────────────────────
for SVC in hmis-web hmis-worker; do
  SVC_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SVC" \
    --query 'services[0].{Running:runningCount,Desired:desiredCount,Status:status}' \
    --output json \
    --region "$REGION" 2>/dev/null || echo '{"Running":0,"Desired":0,"Status":"not-found"}')

  RUNNING=$(echo "$SVC_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Running',0))" 2>/dev/null || echo "?")
  DESIRED=$(echo "$SVC_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Desired',0))" 2>/dev/null || echo "?")

  if [[ "$RUNNING" == "$DESIRED" && "$RUNNING" != "0" ]]; then
    COLOR=$GREEN
  elif [[ "$DESIRED" == "0" ]]; then
    COLOR=$YELLOW
  else
    COLOR=$RED
  fi
  printf "  %-20s ${COLOR}%s/%s tasks${NC}\n" "ECS $SVC:" "$RUNNING" "$DESIRED"
done

# ── ALB ──────────────────────────────────────────────────────────────────────
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names hmis-warehouse-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "not-found")

TG_ARN=$(aws elbv2 describe-target-groups \
  --names hmis-warehouse-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "")

HEALTHY=0
if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
  HEALTHY=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "0")
fi

if [[ "$HEALTHY" -ge 1 ]]; then
  echo -e "  ALB:               ${GREEN}${HEALTHY} healthy targets${NC}"
else
  echo -e "  ALB:               ${YELLOW}${HEALTHY} healthy targets${NC}"
fi

# ── Overall verdict ──────────────────────────────────────────────────────────
echo ""
if [[ "$RDS_STATUS" == "available" && "$REDIS_STATUS" == "available" && "$HEALTHY" -ge 1 ]]; then
  echo -e "  ${GREEN}● SYSTEM IS UP${NC} → http://$ALB_DNS"
elif [[ "$RDS_STATUS" == "stopped" ]]; then
  echo -e "  ${YELLOW}● SYSTEM IS HIBERNATING${NC} — run ./hmis-start.sh to resume"
else
  echo -e "  ${RED}● SYSTEM IS PARTIALLY UP${NC} — check components above"
fi
echo ""
