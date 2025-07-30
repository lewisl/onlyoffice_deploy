#!/bin/bash

# OnlyOffice DocSpace Restart Management Script
# Phase 3: Complete Docker Abstraction - Container Lifecycle Management
#
# This script restarts OnlyOffice services with proper dependency management
# NO Docker knowledge required for administrators

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "OnlyOffice DocSpace Restart Management"
    echo ""
    echo "Usage: onlyoffice-restart [OPTIONS] [SERVICE]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  --ssl                   Restart with SSL configuration"
    echo "  --hard                  Hard restart (stop, remove, start)"
    echo "  --wait SECONDS          Wait time between stop and start (default: 5)"
    echo ""
    echo "Service Groups:"
    echo "  all                     Restart all services (default)"
    echo "  infrastructure          Restart core services only"
    echo "  api                     Restart API services only"
    echo "  frontend                Restart frontend services only"
    echo "  backend                 Restart backend services only"
    echo ""
    echo "Individual Services:"
    echo "  mysql-server            Database service"
    echo "  proxy                   Web proxy service"
    echo "  router                  Internal router service"
    echo "  document-server         Document server service"
    echo "  [service-name]          Any specific OnlyOffice service"
    echo ""
    echo "Examples:"
    echo "  onlyoffice-restart                      # Restart all services"
    echo "  onlyoffice-restart --ssl                # Restart with SSL enabled"
    echo "  onlyoffice-restart mysql-server         # Restart database only"
    echo "  onlyoffice-restart --hard                # Hard restart (full recreation)"
    echo "  onlyoffice-restart --wait 10 proxy      # Restart proxy with 10s wait"
}

# Function to check prerequisites
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
    
    # Check if helper scripts exist
    if [[ ! -f "$SCRIPT_DIR/onlyoffice-stop.sh" ]]; then
        echo -e "${RED}Error: onlyoffice-stop.sh not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/onlyoffice-start.sh" ]]; then
        echo -e "${RED}Error: onlyoffice-start.sh not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
    
    if [[ ! -x "$SCRIPT_DIR/onlyoffice-stop.sh" || ! -x "$SCRIPT_DIR/onlyoffice-start.sh" ]]; then
        echo -e "${RED}Error: Helper scripts are not executable${NC}"
        echo "Run: chmod +x $SCRIPT_DIR/onlyoffice-*.sh"
        exit 1
    fi
}

# Function to restart services
restart_services() {
    local service_filter="$1"
    local use_ssl="$2"
    local hard_restart="$3"
    local wait_time="$4"
    
    echo -e "${BLUE}Restarting OnlyOffice DocSpace Services${NC}"
    echo "$(date)"
    echo ""
    
    if [[ "$hard_restart" == "true" ]]; then
        echo -e "${YELLOW}Performing hard restart (stop, remove, start)${NC}"
    else
        echo -e "${BLUE}Performing graceful restart${NC}"
    fi
    
    if [[ -n "$service_filter" && "$service_filter" != "all" ]]; then
        echo -e "${BLUE}Target: $service_filter services${NC}"
    else
        echo -e "${BLUE}Target: All services${NC}"
    fi
    echo ""
    
    # Step 1: Stop services
    echo -e "${BLUE}Step 1: Stopping services...${NC}"
    local stop_args=""
    if [[ "$hard_restart" == "true" ]]; then
        stop_args="--force --remove"
    fi
    
    if [[ -n "$service_filter" && "$service_filter" != "all" ]]; then
        "$SCRIPT_DIR/onlyoffice-stop.sh" $stop_args "$service_filter"
    else
        "$SCRIPT_DIR/onlyoffice-stop.sh" $stop_args
    fi
    
    # Step 2: Wait
    if [[ $wait_time -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Waiting ${wait_time} seconds for cleanup...${NC}"
        sleep "$wait_time"
    fi
    
    # Step 3: Start services
    echo ""
    echo -e "${BLUE}Step 2: Starting services...${NC}"
    local start_args=""
    if [[ "$use_ssl" == "true" ]]; then
        start_args="--ssl"
    fi
    
    if [[ -n "$service_filter" && "$service_filter" != "all" ]]; then
        "$SCRIPT_DIR/onlyoffice-start.sh" $start_args "$service_filter"
    else
        "$SCRIPT_DIR/onlyoffice-start.sh" $start_args
    fi
    
    echo ""
    echo -e "${GREEN}✓ Restart operation completed${NC}"
    echo ""
    echo "Use 'onlyoffice-status' to verify all services are running correctly"
    
    # Additional wait for services to stabilize
    if [[ "$service_filter" == "all" || -z "$service_filter" ]]; then
        echo ""
        echo -e "${YELLOW}Allowing extra time for all services to stabilize...${NC}"
        sleep 15
        
        # Quick status check
        local running_count
        running_count=$(docker ps --format "{{.Names}}" | grep "^onlyoffice-" | wc -l)
        echo -e "${BLUE}Quick Status Check: $running_count OnlyOffice containers running${NC}"
        
        if [[ $running_count -ge 15 ]]; then
            echo -e "${GREEN}✓ Restart appears successful${NC}"
        else
            echo -e "${YELLOW}⚠ Some services may still be starting - check status in a few minutes${NC}"
        fi
    fi
}

# Function to show current status before restart
show_pre_restart_status() {
    local service_filter="$1"
    
    echo -e "${BLUE}Current Status (before restart):${NC}"
    
    # Count running containers
    local total_running
    total_running=$(docker ps --format "{{.Names}}" | grep "^onlyoffice-" | wc -l)
    
    if [[ $total_running -eq 0 ]]; then
        echo -e "${RED}No OnlyOffice services currently running${NC}"
        echo "This will be a fresh start rather than a restart"
    else
        echo -e "${GREEN}$total_running OnlyOffice services currently running${NC}"
        
        # Show unhealthy services if any
        local unhealthy=0
        for container in $(docker ps --format "{{.Names}}" | grep "^onlyoffice-"); do
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            if [[ "$health" == "unhealthy" ]]; then
                if [[ $unhealthy -eq 0 ]]; then
                    echo -e "${YELLOW}Unhealthy services:${NC}"
                fi
                echo -e "  ${YELLOW}⚠${NC} ${container#onlyoffice-}"
                ((unhealthy++))
            fi
        done
        
        if [[ $unhealthy -gt 0 ]]; then
            echo -e "${YELLOW}Restart will address $unhealthy unhealthy service(s)${NC}"
        fi
    fi
    echo ""
}

# Main function
main() {
    local service_filter="" use_ssl="false" hard_restart="false" wait_time="5"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --ssl)
                use_ssl="true"
                shift
                ;;
            --hard)
                hard_restart="true"
                shift
                ;;
            --wait)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    wait_time="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --wait requires a number${NC}"
                    exit 1
                fi
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$service_filter" ]]; then
                    service_filter="$1"
                else
                    echo -e "${RED}Error: Only one service filter allowed${NC}"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    check_prerequisites
    show_pre_restart_status "$service_filter"
    restart_services "$service_filter" "$use_ssl" "$hard_restart" "$wait_time"
}

# Run main function
main "$@"