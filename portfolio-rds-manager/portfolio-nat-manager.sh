#!/bin/bash

###############################################################################
# Portfolio NAT Gateway Manager - CLI Tool
# 
# Manages NAT Gateway lifecycle (delete/recreate) to save costs during prototyping
#
# Usage:
#   ./portfolio-nat-manager.sh status
#   ./portfolio-nat-manager.sh list
#   ./portfolio-nat-manager.sh stop <nat-name>
#   ./portfolio-nat-manager.sh start <nat-name>
#   ./portfolio-nat-manager.sh cost-estimate
#
# Features:
#   - Delete NAT Gateway to stop charges
#   - Recreate with same configuration
#   - Preserve Elastic IP address
#   - Update route tables automatically
#   - Track state in local JSON file
#
###############################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/nat-portfolio-config.yaml"
STATE_FILE="${SCRIPT_DIR}/.portfolio-nat-state.json"
REGION="us-east-1"
AWS_PROFILE="${AWS_PROFILE:-housing-prototype}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

die() {
    log_error "$@"
    exit 1
}

# Check if yq is installed
check_dependencies() {
    local missing=()
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing+=("yq")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with:"
        log_info "  brew install awscli yq jq  # macOS"
        log_info "  sudo apt-get install awscli yq jq  # Ubuntu"
        exit 1
    fi
}

# Load config from YAML
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        die "Config file not found: $CONFIG_FILE\n  Set up with: cp nat-portfolio-config.example.yaml nat-portfolio-config.yaml"
    fi
}

# Get NAT config by name
get_nat_config() {
    local nat_name="$1"
    yq eval ".nat_gateways[] | select(.name == \"$nat_name\")" "$CONFIG_FILE"
}

# Get all NAT names
list_all_nats() {
    yq eval '.nat_gateways[].name' "$CONFIG_FILE"
}

# Initialize state file
init_state_file() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "{}" > "$STATE_FILE"
    fi
}

# Save state
save_state() {
    local nat_name="$1"
    local state_key="$2"
    local state_value="$3"
    
    init_state_file
    
    jq --arg name "$nat_name" --arg key "$state_key" --arg value "$state_value" \
        '.[$name][$key] = $value' "$STATE_FILE" > "${STATE_FILE}.tmp" && \
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Get state
get_state() {
    local nat_name="$1"
    local state_key="$2"
    
    init_state_file
    
    jq -r --arg name "$nat_name" --arg key "$state_key" \
        '.[$name][$key] // empty' "$STATE_FILE"
}

# Get NAT Gateway status from AWS
get_nat_status() {
    local nat_name="$1"
    
    # First check if we have a saved NAT Gateway ID
    local saved_nat_id=$(get_state "$nat_name" "nat_gateway_id")
    
    if [ -z "$saved_nat_id" ]; then
        echo "deleted"
        return
    fi
    
    # Check if it still exists in AWS
    local status=$(aws ec2 describe-nat-gateways \
        --nat-gateway-ids "$saved_nat_id" \
        --region "$REGION" --profile "$AWS_PROFILE" \
        --query 'NatGateways[0].State' \
        --output text 2>/dev/null || echo "deleted")
    
    echo "$status"
}

###############################################################################
# Core Commands
###############################################################################

cmd_status() {
    load_config
    init_state_file
    
    echo ""
    log_info "Portfolio NAT Gateway Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_cost_running=0
    local total_cost_deleted=0
    
    while IFS= read -r nat_name; do
        local config=$(get_nat_config "$nat_name")
        local az=$(echo "$config" | yq eval '.availability_zone' -)
        
        local status=$(get_nat_status "$nat_name")
        local nat_id=$(get_state "$nat_name" "nat_gateway_id")
        local eip=$(get_state "$nat_name" "elastic_ip")
        
        # Get IP address if running
        local ip_address="N/A"
        if [ "$status" = "available" ]; then
            ip_address=$(aws ec2 describe-nat-gateways \
                --nat-gateway-ids "$nat_id" \
                --region "$REGION" --profile "$AWS_PROFILE" \
                --query 'NatGateways[0].NatGatewayAddresses[0].PublicIp' \
                --output text 2>/dev/null || echo "N/A")
            
            total_cost_running=$((total_cost_running + 40))  # ~$40/month
        else
            total_cost_deleted=$((total_cost_deleted + 1))   # ~$0.32/month for EIP
        fi
        
        # Format status
        local status_icon=""
        if [ "$status" = "available" ]; then
            status_icon="✓ Running"
        else
            status_icon="✗ Deleted"
        fi
        
        echo ""
        echo -e "  ${status_icon}"
        echo "    Name:    $nat_name"
        echo "    AZ:      $az"
        echo "    Status:  $status"
        if [ -n "$nat_id" ] && [ "$nat_id" != "null" ]; then
            echo "    NAT ID:  $nat_id"
        fi
        if [ -n "$eip" ] && [ "$eip" != "null" ]; then
            echo "    EIP:     $eip"
        fi
        if [ "$ip_address" != "N/A" ]; then
            echo "    Public IP: $ip_address"
        fi
        
        # Show cost
        if [ "$status" = "available" ]; then
            echo "    Cost:    ~\$40/month"
        else
            echo "    Cost:    ~\$0.32/month (EIP only)"
        fi
        
        # Last action
        local last_action=$(get_state "$nat_name" "last_action")
        if [ -n "$last_action" ]; then
            echo "    Last:    $last_action"
        fi
        
    done < <(list_all_nats)
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💰 Cost Summary"
    echo "  Running:  \$${total_cost_running}/month"
    echo "  Deleted:  \$${total_cost_deleted}/month (EIP storage only)"
    echo "  Total:    \$$(echo "$total_cost_running + $total_cost_deleted" | bc)/month"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

cmd_list() {
    load_config
    
    log_info "Available NAT Gateways:"
    echo ""
    
    while IFS= read -r nat_name; do
        local config=$(get_nat_config "$nat_name")
        local az=$(echo "$config" | yq eval '.availability_zone' -)
        local subnet=$(echo "$config" | yq eval '.subnet_id' -)
        
        echo "  • ${BLUE}${nat_name}${NC}"
        echo "    AZ:     $az"
        echo "    Subnet: $subnet"
        echo ""
    done < <(list_all_nats)
}

cmd_stop() {
    local nat_name="$1"
    
    load_config
    init_state_file
    
    log_info "Stopping NAT Gateway: $nat_name"
    
    local config=$(get_nat_config "$nat_name")
    [ -z "$config" ] && die "NAT Gateway not found: $nat_name"
    
    # Get saved NAT Gateway ID
    local nat_id=$(get_state "$nat_name" "nat_gateway_id")

    # If saved ID is missing/stale, search AWS by Name tag
    local lookup_id="$nat_id"
    if [ -z "$lookup_id" ] || [ "$lookup_id" = "null" ]; then
        lookup_id=""
    else
        # Verify the saved ID is still active; if not, fall through to name lookup
        local saved_status=$(aws ec2 describe-nat-gateways \
            --nat-gateway-ids "$lookup_id" \
            --region "$REGION" --profile "$AWS_PROFILE" \
            --query 'NatGateways[0].State' \
            --output text 2>/dev/null || echo "not-found")
        if [ "$saved_status" = "deleted" ] || [ "$saved_status" = "deleting" ] || [ "$saved_status" = "not-found" ] || [ "$saved_status" = "None" ]; then
            lookup_id=""
        fi
    fi

    # Secondary lookup: find active gateway by Name tag
    if [ -z "$lookup_id" ]; then
        log_info "Saved ID not active, searching by Name tag: $nat_name"
        lookup_id=$(aws ec2 describe-nat-gateways \
            --filter "Name=tag:Name,Values=$nat_name" "Name=state,Values=available,pending" \
            --region "$REGION" --profile "$AWS_PROFILE" \
            --query 'NatGateways[0].NatGatewayId' \
            --output text 2>/dev/null || echo "")
        if [ "$lookup_id" = "None" ] || [ "$lookup_id" = "null" ]; then
            lookup_id=""
        fi
    fi

    if [ -z "$lookup_id" ]; then
        log_warning "No active NAT Gateway found for: $nat_name"
        save_state "$nat_name" "nat_gateway_id" ""
        save_state "$nat_name" "status" "deleted"
        save_state "$nat_name" "last_action" "State synced at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        log_info "State file synced — run 'start' when you need it again"
        exit 0
    fi

    # Use the resolved ID going forward
    nat_id="$lookup_id"
    save_state "$nat_name" "nat_gateway_id" "$nat_id"
    log_info "Resolved NAT Gateway ID: $nat_id"
    
    # Confirm action
    read -p "Continue? (y/n): " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    [[ ! "$confirm" =~ ^(y|yes)$ ]] && { log_warning "Cancelled"; exit 0; }
    
    # Get route tables that use this NAT Gateway
    local route_tables=$(echo "$config" | yq eval '.route_tables[]' -)
    
    # Update route tables to remove the NAT Gateway route (optional)
    if [ -n "$route_tables" ]; then
        log_info "Updating route tables to remove NAT Gateway route..."
        
        while IFS= read -r rt_id; do
            if [ -n "$rt_id" ] && [ "$rt_id" != "null" ]; then
                # Try to delete the route (will fail if NAT is not the target)
                aws ec2 delete-route \
                    --route-table-id "$rt_id" \
                    --destination-cidr-block 0.0.0.0/0 \
                    --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null || true
                log_info "Removed route from $rt_id"
            fi
        done <<< "$route_tables"
    fi
    
    # Delete NAT Gateway
    log_info "Deleting NAT Gateway: $nat_id"
    aws ec2 delete-nat-gateway \
        --nat-gateway-id "$nat_id" \
        --region "$REGION" --profile "$AWS_PROFILE" || die "Failed to delete NAT Gateway"
    
    # Wait for deletion
    log_info "Waiting for NAT Gateway to be deleted..."
    aws ec2 wait nat-gateway-deleted \
        --nat-gateway-ids "$nat_id" \
        --region "$REGION" --profile "$AWS_PROFILE" || die "Timeout waiting for NAT Gateway deletion"
    
    # Update state
    save_state "$nat_name" "status" "deleted"
    save_state "$nat_name" "nat_gateway_id" ""
    save_state "$nat_name" "last_action" "Deleted at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    log_success "NAT Gateway deleted: $nat_name"
    log_info "Saving ~\$40/month"
    log_info "Elastic IP preserved: $(get_state "$nat_name" "elastic_ip")"
}

cmd_start() {
    local nat_name="$1"
    
    load_config
    init_state_file
    
    log_info "Starting NAT Gateway: $nat_name"
    
    local config=$(get_nat_config "$nat_name")
    [ -z "$config" ] && die "NAT Gateway not found: $nat_name"
    
    # Get configuration
    local subnet_id=$(echo "$config" | yq eval '.subnet_id' -)
    local eip_alloc=$(get_state "$nat_name" "elastic_ip_allocation_id")
    
    [ -z "$subnet_id" ] && die "Subnet ID not configured for $nat_name"
    [ -z "$eip_alloc" ] && die "Elastic IP not configured for $nat_name"
    
    # Create NAT Gateway
    log_info "Creating NAT Gateway in subnet: $subnet_id"
    local nat_response=$(aws ec2 create-nat-gateway \
        --subnet-id "$subnet_id" \
        --allocation-id "$eip_alloc" \
        --region "$REGION" --profile "$AWS_PROFILE" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$nat_name},{Key=ManagedBy,Value=PortfolioNATManager}]" \
        --output json)
    
    local new_nat_id=$(echo "$nat_response" | jq -r '.NatGateway.NatGatewayId')
    [ -z "$new_nat_id" ] && die "Failed to create NAT Gateway"
    
    log_info "NAT Gateway created: $new_nat_id"
    log_info "Waiting for NAT Gateway to be available (2-3 minutes)..."
    
    # Wait for availability
    aws ec2 wait nat-gateway-available \
        --nat-gateway-ids "$new_nat_id" \
        --region "$REGION" --profile "$AWS_PROFILE" || die "Timeout waiting for NAT Gateway"
    
    # Get new IP address
    local new_ip=$(aws ec2 describe-nat-gateways \
        --nat-gateway-ids "$new_nat_id" \
        --region "$REGION" --profile "$AWS_PROFILE" \
        --query 'NatGateways[0].NatGatewayAddresses[0].PublicIp' \
        --output text)
    
    log_success "NAT Gateway available: $new_nat_id"
    log_info "Public IP: $new_ip"
    
    # Update route tables
    local route_tables=$(echo "$config" | yq eval '.route_tables[]' -)
    local route_dest=$(echo "$config" | yq eval '.route_destination' -)
    
    if [ -n "$route_tables" ]; then
        log_info "Updating route tables..."

        while IFS= read -r rt_id; do
            if [ -n "$rt_id" ] && [ "$rt_id" != "null" ]; then
                # Try to replace route first (if it exists)
                if aws ec2 replace-route \
                    --route-table-id "$rt_id" \
                    --destination-cidr-block "$route_dest" \
                    --nat-gateway-id "$new_nat_id" \
                    --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null; then
                    log_info "✓ Updated route in $rt_id"
                else
                    # Route doesn't exist, create it
                    if aws ec2 create-route \
                        --route-table-id "$rt_id" \
                        --destination-cidr-block "$route_dest" \
                        --nat-gateway-id "$new_nat_id" \
                        --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null; then
                        log_info "✓ Created route in $rt_id"
                    else
                        log_warning "✗ Failed to update/create route in $rt_id"
                    fi
                fi
            fi
        done <<< "$route_tables"
    fi
    
    # Update state
    save_state "$nat_name" "status" "available"
    save_state "$nat_name" "nat_gateway_id" "$new_nat_id"
    save_state "$nat_name" "public_ip" "$new_ip"
    save_state "$nat_name" "last_action" "Created at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    log_success "NAT Gateway started: $nat_name"
    log_info "Monthly cost resumed: ~\$40/month"
}

cmd_cost_estimate() {
    load_config
    
    echo ""
    log_info "Monthly Cost Estimates"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_running=0
    local total_deleted=0
    
    while IFS= read -r nat_name; do
        local status=$(get_nat_status "$nat_name")
        
        local cost_running=40
        local cost_deleted=1
        
        if [ "$status" = "available" ]; then
            total_running=$((total_running + cost_running))
        else
            total_deleted=$((total_deleted + cost_deleted))
        fi
        
        echo ""
        echo "  $nat_name"
        echo "    Running:  \$$cost_running/month (all month)"
        echo "    Deleted:  \$$cost_deleted/month (EIP only)"
        
        # Calculate savings for various uptime percentages
        local savings_25=$(echo "$cost_running * 0.75" | bc | cut -d'.' -f1)
        local savings_10=$(echo "$cost_running * 0.90" | bc | cut -d'.' -f1)
        
        echo "    If 25% uptime: \$$(echo "$cost_running * 0.25 + $cost_deleted * 0.75" | bc | cut -d'.' -f1)/month (\$$savings_25 saved)"
        echo "    If 10% uptime: \$$(echo "$cost_running * 0.10 + $cost_deleted * 0.90" | bc | cut -d'.' -f1)/month (\$$savings_10 saved)"
        
    done < <(list_all_nats)
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Total Monthly Costs"
    echo "  All running:  \$${total_running}/month"
    echo "  All deleted:  \$${total_deleted}/month"
    echo ""
    echo "💡 Recommendation for prototyping:"
    echo "  Delete when not developing/testing"
    echo "  Recreate when you need it (2-3 minutes)"
    echo "  Potential savings: ~\$30-35/month per NAT Gateway"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

###############################################################################
# Main
###############################################################################

main() {
    check_dependencies
    
    case "${1:-help}" in
        status)
            cmd_status
            ;;
        stop)
            [ -z "${2:-}" ] && die "Usage: stop <nat-name>"
            cmd_stop "$2"
            ;;
        start)
            [ -z "${2:-}" ] && die "Usage: start <nat-name>"
            cmd_start "$2"
            ;;
        list)
            cmd_list
            ;;
        cost-estimate|costs)
            cmd_cost_estimate
            ;;
        *)
            cat << 'EOF'
Portfolio NAT Gateway Manager - Lifecycle Management

Usage:
  portfolio-nat-manager.sh status              Show status of all NAT Gateways
  portfolio-nat-manager.sh list                List all configured NAT Gateways
  portfolio-nat-manager.sh stop <n>         Stop (delete) a NAT Gateway
  portfolio-nat-manager.sh start <n>        Start (create) a NAT Gateway
  portfolio-nat-manager.sh cost-estimate       Show monthly cost estimates

Examples:
  ./portfolio-nat-manager.sh status
  ./portfolio-nat-manager.sh stop primary-nat
  ./portfolio-nat-manager.sh start primary-nat
  ./portfolio-nat-manager.sh cost-estimate

Configuration:
  Edit nat-portfolio-config.yaml to add/remove NAT Gateways and configure
  subnets, route tables, and Elastic IPs.

Notes:
  - NAT Gateways cannot be paused, only deleted and recreated
  - Deleting stops all charges except ~$0.32/month for the Elastic IP
  - Recreating takes 2-3 minutes
  - Route tables are updated automatically

EOF
            ;;
    esac
}

main "$@"
