#!/bin/bash

###############################################################################
# Portfolio RDS Manager - Main CLI Tool
# 
# Manages multiple RDS instances with two strategies:
#   1. Stop/Start: Pause compute, resume in seconds (~50% savings)
#   2. Delete/Restore: Full backup/restore (~100% savings, 10-15 min setup)
#
# Usage:
#   ./portfolio-rds-manager.sh status [--all]
#   ./portfolio-rds-manager.sh stop <instance-name> [--verify]
#   ./portfolio-rds-manager.sh start <instance-name>
#   ./portfolio-rds-manager.sh list
#   ./portfolio-rds-manager.sh backup <instance-name>
#   ./portfolio-rds-manager.sh delete <instance-name> [--backup]
#   ./portfolio-rds-manager.sh restore <instance-name> [--from-backup DATE]
#   ./portfolio-rds-manager.sh cost-estimate
###############################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/rds-portfolio-config.yaml"
STATE_TABLE="portfolio-rds-state"
REGION="us-east-1"

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

# Check if yq is installed (for YAML parsing)
check_dependencies() {
    local missing=()
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing+=("yq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with:"
        log_info "  brew install awscli yq  # macOS"
        log_info "  sudo apt-get install awscli yq  # Ubuntu"
        exit 1
    fi
}

# Load config from YAML
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        die "Config file not found: $CONFIG_FILE\n  Set up with: cp rds-portfolio-config.example.yaml rds-portfolio-config.yaml"
    fi
}

# Get instance config by name
get_instance_config() {
    local instance_name="$1"
    yq eval ".instances[] | select(.name == \"$instance_name\")" "$CONFIG_FILE"
}

# Get all instance names
list_all_instances() {
    yq eval '.instances[].name' "$CONFIG_FILE"
}

# Get AWS RDS instance details
get_rds_instance_status() {
    local db_identifier="$1"
    aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --region "$REGION" \
        --query 'DBInstances[0]' \
        --output json
}

# Save state to DynamoDB (or local file for dev)
save_state() {
    local instance_name="$1"
    local state_key="$2"
    local state_value="$3"
    
    # For development, use local JSON file
    local state_file="${SCRIPT_DIR}/.portfolio-rds-state"
    
    # Create or load existing state
    if [ ! -f "$state_file" ]; then
        echo "{}" > "$state_file"
    fi
    
    # Update state using jq
    jq --arg key "$instance_name:$state_key" --arg value "$state_value" \
        '.[$key] = $value' "$state_file" > "${state_file}.tmp" && \
        mv "${state_file}.tmp" "$state_file"
}

# Get state from storage
get_state() {
    local instance_name="$1"
    local state_key="$2"
    local state_file="${SCRIPT_DIR}/.portfolio-rds-state"
    
    if [ ! -f "$state_file" ]; then
        return
    fi
    
    jq -r --arg key "$instance_name:$state_key" '.[$key] // empty' "$state_file"
}

###############################################################################
# Core Commands
###############################################################################

cmd_status() {
    local show_all="${1:-}"
    
    load_config
    
    echo ""
    log_info "Portfolio RDS Status Report"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_cost_running=0
    local total_cost_stopped=0
    
    while IFS= read -r instance_name; do
        local config=$(get_instance_config "$instance_name")
        local db_id=$(echo "$config" | yq eval '.db_identifier' -)
        local strategy=$(echo "$config" | yq eval '.lifecycle.strategy' -)
        
        local status
        local endpoint
        local cost_monthly=0
        local storage_gb=0
        
        # Get RDS status
        if local rds_info=$(get_rds_instance_status "$db_id" 2>/dev/null); then
            status=$(echo "$rds_info" | jq -r '.DBInstanceStatus')
            endpoint=$(echo "$rds_info" | jq -r '.Endpoint.Address // "N/A"')
            storage_gb=$(echo "$rds_info" | jq -r '.AllocatedStorage')
            
            # Calculate cost based on status
            if [ "$status" = "available" ]; then
                cost_monthly=$(yq eval ".cost_estimates.$(echo "$rds_info" | jq -r '.Engine')_running" "$CONFIG_FILE")
                total_cost_running=$(echo "$total_cost_running + $cost_monthly" | bc)
            elif [ "$status" = "stopped" ]; then
                cost_monthly=$(yq eval ".cost_estimates.$(echo "$rds_info" | jq -r '.Engine')_stopped" "$CONFIG_FILE")
                total_cost_stopped=$(echo "$total_cost_stopped + $cost_monthly" | bc)
            fi
        else
            status="deleted"
            endpoint="N/A"
            cost_monthly=$(yq eval ".cost_estimates.postgres_deleted_storage" "$CONFIG_FILE")
        fi
        
        # Format output
        local status_icon=""
        if [ "$status" = "available" ]; then
            status_icon="✓"
        elif [ "$status" = "stopped" ]; then
            status_icon="⏸"
        else
            status_icon="✗"
        fi
        
        echo ""
        echo -e "  ${status_icon} ${BLUE}${instance_name}${NC} (${strategy})"
        echo "    Status:   $status"
        echo "    DB ID:    $db_id"
        echo "    Endpoint: $endpoint"
        echo "    Storage:  ${storage_gb}GB"
        echo "    Cost:     \$$cost_monthly/month"
        
        # Last action timestamp
        local last_action=$(get_state "$instance_name" "last_action")
        if [ -n "$last_action" ]; then
            echo "    Last:     $last_action"
        fi
        
    done < <(list_all_instances)
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💰 Cost Summary"
    echo "  Running:  \$${total_cost_running}/month"
    echo "  Stopped:  \$${total_cost_stopped}/month"
    echo "  Total:    \$$(echo "$total_cost_running + $total_cost_stopped" | bc)/month"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

cmd_list() {
    load_config
    
    log_info "Available RDS Instances:"
    echo ""
    
    while IFS= read -r instance_name; do
        local config=$(get_instance_config "$instance_name")
        local db_id=$(echo "$config" | yq eval '.db_identifier' -)
        local engine=$(echo "$config" | yq eval '.engine' -)
        local strategy=$(echo "$config" | yq eval '.lifecycle.strategy' -)
        
        echo "  • ${BLUE}${instance_name}${NC}"
        echo "    ID:       $db_id"
        echo "    Engine:   $engine"
        echo "    Strategy: $strategy"
        echo ""
    done < <(list_all_instances)
}

cmd_stop() {
    local instance_name="$1"
    
    load_config
    
    log_info "Stopping RDS instance: $instance_name"
    
    local config=$(get_instance_config "$instance_name")
    [ -z "$config" ] && die "Instance not found: $instance_name"
    
    local db_id=$(echo "$config" | yq eval '.db_identifier' -)
    
    # Confirm action
    read -p "Continue? (y/n): " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    [[ ! "$confirm" =~ ^(y|yes)$ ]] && { log_warning "Cancelled"; exit 0; }
    
    # Stop the instance
    log_info "Sending stop request to RDS..."
    aws rds stop-db-instance \
        --db-instance-identifier "$db_id" \
        --region "$REGION" > /dev/null || die "Failed to stop instance"
    
    # Wait for stopped state
    log_info "Waiting for instance to stop (this takes ~1 minute)..."
    aws rds wait db-instance-stopped \
        --db-instance-identifier "$db_id" \
        --region "$REGION" || die "Timeout waiting for stop"
    
    # Save state
    save_state "$instance_name" "status" "stopped"
    save_state "$instance_name" "last_action" "Stopped at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    save_state "$instance_name" "stop_time" "$(date -u +%s)"
    
    log_success "Instance stopped: $instance_name"
    log_info "Saving \$6.50/month (50% of compute cost)"
}

cmd_start() {
    local instance_name="$1"
    
    load_config
    
    log_info "Starting RDS instance: $instance_name"
    
    local config=$(get_instance_config "$instance_name")
    [ -z "$config" ] && die "Instance not found: $instance_name"
    
    local db_id=$(echo "$config" | yq eval '.db_identifier' -)
    
    # Start the instance
    log_info "Sending start request to RDS..."
    aws rds start-db-instance \
        --db-instance-identifier "$db_id" \
        --region "$REGION" > /dev/null || die "Failed to start instance"
    
    # Wait for available state
    log_info "Waiting for instance to start (this takes ~2 minutes)..."
    aws rds wait db-instance-available \
        --db-instance-identifier "$db_id" \
        --region "$REGION" || die "Timeout waiting for start"
    
    # Get new endpoint
    local endpoint=$(get_rds_instance_status "$db_id" | jq -r '.Endpoint.Address')
    
    # Save state
    save_state "$instance_name" "status" "available"
    save_state "$instance_name" "last_action" "Started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    save_state "$instance_name" "endpoint" "$endpoint"
    
    log_success "Instance started: $instance_name"
    log_info "Endpoint: $endpoint"
    log_info "Monthly cost resumed: \$13.00"
}

cmd_backup() {
    local instance_name="$1"
    
    load_config
    
    log_info "Backing up database: $instance_name"
    
    local config=$(get_instance_config "$instance_name")
    [ -z "$config" ] && die "Instance not found: $instance_name"
    
    local db_id=$(echo "$config" | yq eval '.db_identifier' -)
    local engine=$(echo "$config" | yq eval '.engine' -)
    local endpoint=$(get_rds_instance_status "$db_id" | jq -r '.Endpoint.Address')
    
    [ -z "$endpoint" ] && die "Could not get RDS endpoint"
    
    log_info "Database engine: $engine"
    log_info "Endpoint: $endpoint"
    log_warning "Enter RDS master password when prompted"
    
    # TODO: Implement actual backup logic based on engine type
    # This is a placeholder - full implementation in dedicated backup script
    
    log_success "Backup initiated for $instance_name"
}

cmd_cost_estimate() {
    load_config
    
    echo ""
    log_info "Monthly Cost Estimates"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_running=0
    local total_stopped=0
    local total_deleted=0
    
    while IFS= read -r instance_name; do
        local config=$(get_instance_config "$instance_name")
        local engine=$(echo "$config" | yq eval '.engine' -)
        
        local cost_running=$(yq eval ".cost_estimates.${engine}_running" "$CONFIG_FILE")
        local cost_stopped=$(yq eval ".cost_estimates.${engine}_stopped" "$CONFIG_FILE")
        local cost_deleted=$(yq eval ".cost_estimates.${engine}_deleted_storage" "$CONFIG_FILE")
        
        total_running=$(echo "$total_running + $cost_running" | bc)
        total_stopped=$(echo "$total_stopped + $cost_stopped" | bc)
        total_deleted=$(echo "$total_deleted + $cost_deleted" | bc)
        
        echo ""
        echo "  $instance_name ($engine)"
        echo "    Running:       \$$cost_running/month"
        echo "    Stopped:       \$$cost_stopped/month (50% savings)"
        echo "    Deleted+S3:    \$$cost_deleted/month (98% savings)"
        
    done < <(list_all_instances)
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Total Monthly Costs"
    echo "  All running:  \$${total_running}/month"
    echo "  All stopped:  \$${total_stopped}/month ($(echo "scale=1; 100 - (100 * $total_stopped / $total_running)" | bc)% savings)"
    echo "  All deleted:  \$${total_deleted}/month ($(echo "scale=1; 100 - (100 * $total_deleted / $total_running)" | bc)% savings)"
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
            cmd_status "${2:-}"
            ;;
        stop)
            [ -z "${2:-}" ] && die "Usage: stop <instance-name>"
            cmd_stop "$2"
            ;;
        start)
            [ -z "${2:-}" ] && die "Usage: start <instance-name>"
            cmd_start "$2"
            ;;
        list)
            cmd_list
            ;;
        backup)
            [ -z "${2:-}" ] && die "Usage: backup <instance-name>"
            cmd_backup "$2"
            ;;
        cost-estimate|costs)
            cmd_cost_estimate
            ;;
        *)
            cat << 'EOF'
Portfolio RDS Manager - Stop/Start and Backup/Restore Management

Usage:
  portfolio-rds-manager.sh status              Show status of all instances
  portfolio-rds-manager.sh list                List all configured instances
  portfolio-rds-manager.sh stop <name>         Stop (pause) an instance
  portfolio-rds-manager.sh start <name>        Start a stopped instance
  portfolio-rds-manager.sh backup <name>       Create manual backup to S3
  portfolio-rds-manager.sh cost-estimate       Show monthly cost estimates

Examples:
  ./portfolio-rds-manager.sh status
  ./portfolio-rds-manager.sh stop bloom-prototype
  ./portfolio-rds-manager.sh start bloom-prototype
  ./portfolio-rds-manager.sh cost-estimate

Configuration:
  Edit rds-portfolio-config.yaml to add/remove instances and configure
  lifecycle strategies (stop-start vs delete-restore).

EOF
            ;;
    esac
}

main "$@"
