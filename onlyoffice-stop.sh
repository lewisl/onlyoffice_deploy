#!/bin/bash

# OnlyOffice DocSpace Stop Management Script
# Phase 3: Complete Docker Abstraction - Container Lifecycle Management
#
# This script stops OnlyOffice services in proper reverse dependency order
# NO Docker knowledge required for administrators

set -e

COMPOSE_DIR="/app/onlyoffice"
COMPOSE_FILES="-f $COMPOSE_DIR/docspace.yml -f $COMPOSE_DIR/db.yml -f $COMPOSE_DIR/ds.yml -f $COMPOSE_DIR/proxy.yml -f $COMPOSE_DIR/proxy-ssl.yml"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "OnlyOffice DocSpace Stop Management"
    echo ""
    echo "Usage: onlyoffice-stop [OPTIONS] [SERVICE]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  --graceful              Graceful shutdown (default, 30s timeout)"
    echo "  --force                 Force stop immediately"
    echo "  --remove                Remove containers after stopping"
    echo ""
    echo "Service Groups:"
    echo "  all                     Stop all services (default)"
    echo "  infrastructure          Stop core services only"
    echo "  api                     Stop API services only"
    echo "  frontend                Stop frontend services only"
    echo "  backend                 Stop backend services only"
    echo ""
    echo "Individual Services:"
    echo "  mysql-server            Database service"
    echo "  proxy                   Web proxy service"
    echo "  router                  Internal router service"
    echo "  document-server         Document server service"
    echo "  [service-name]          Any specific OnlyOffice service"
    echo ""
    echo "Examples:"
    echo "  onlyoffice-stop                     # Stop all services gracefully"
    echo "  onlyoffice-stop --force             # Force stop all services"
    echo "  onlyoffice-stop mysql-server        # Stop database only"
    echo "  onlyoffice-stop --remove            # Stop and remove containers"
}

# Function to check prerequisites
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker not found${NC}"
        exit 1
    fi
}

# Function to stop specific container
stop_container() {
    local container_name="$1"
    local force="$2"
    local timeout="${3:-30}"
    
    # Check if container exists and is running
    if ! docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "  ${YELLOW}ℹ${NC} $container_name (not running)"
        return 0
    fi
    
    echo -e "  ${BLUE}Stopping${NC} $container_name..."
    
    if [[ "$force" == "true" ]]; then
        docker kill "$container_name" >/dev/null 2>&1 || true
    else
        docker stop --time="$timeout" "$container_name" >/dev/null 2>&1 || true
    fi
    
    # Verify it stopped
    if ! docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "  ${GREEN}✓${NC} $container_name stopped"
    else
        echo -e "  ${RED}✗${NC} $container_name failed to stop"
        return 1
    fi
}

# Function to remove container
remove_container() {
    local container_name="$1"
    
    if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "  ${BLUE}Removing${NC} $container_name..."
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo -e "  ${GREEN}✓${NC} $container_name removed"
    fi
}

# Function to get service containers in stop order (reverse dependency)
get_containers_stop_order() {
    local service_filter="$1"
    
    case "$service_filter" in
        "all"|"")
            # Stop in reverse dependency order: frontend -> api -> backend -> infrastructure
            echo "onlyoffice-studio onlyoffice-login onlyoffice-files onlyoffice-files-services onlyoffice-doceditor onlyoffice-socket onlyoffice-studio-notify"
            echo "onlyoffice-api onlyoffice-api-system onlyoffice-sdk"  
            echo "onlyoffice-people-server onlyoffice-backup onlyoffice-backup-background-tasks onlyoffice-ssoauth onlyoffice-clear-events"
            echo "onlyoffice-router onlyoffice-proxy onlyoffice-document-server onlyoffice-mysql-server"
            ;;
        "infrastructure")
            echo "onlyoffice-router onlyoffice-proxy onlyoffice-document-server onlyoffice-mysql-server"
            ;;
        "api")
            echo "onlyoffice-api onlyoffice-api-system onlyoffice-sdk"
            ;;
        "frontend")
            echo "onlyoffice-studio onlyoffice-login onlyoffice-files onlyoffice-files-services onlyoffice-doceditor onlyoffice-socket onlyoffice-studio-notify"
            ;;
        "backend")
            echo "onlyoffice-people-server onlyoffice-backup onlyoffice-backup-background-tasks onlyoffice-ssoauth onlyoffice-clear-events"
            ;;
        *)
            # Individual service
            if [[ "$service_filter" == onlyoffice-* ]]; then
                echo "$service_filter"
            else
                echo "onlyoffice-$service_filter"
            fi
            ;;
    esac
}

# Function to stop services
stop_services() {
    local service_filter="$1"
    local force="$2"
    local remove="$3"
    local timeout="30"
    
    if [[ "$force" == "true" ]]; then
        timeout="0"
    fi
    
    echo -e "${BLUE}Stopping OnlyOffice DocSpace Services${NC}"
    echo "$(date)"
    echo ""
    
    if [[ "$force" == "true" ]]; then
        echo -e "${YELLOW}Using force stop (immediate termination)${NC}"
    else
        echo -e "${BLUE}Using graceful stop (${timeout}s timeout per service)${NC}"
    fi
    echo ""
    
    # Get containers to stop
    local containers
    containers=$(get_containers_stop_order "$service_filter")
    
    if [[ -z "$containers" ]]; then
        echo -e "${RED}Error: Unknown service '$service_filter'${NC}"
        echo "Use --help to see available services"
        exit 1
    fi
    
    # Stop containers
    local stopped=0 total=0 failed=0
    
    for container in $containers; do
        ((total++))
        if stop_container "$container" "$force" "$timeout"; then
            ((stopped++))
        else
            ((failed++))
        fi
    done
    
    # Remove containers if requested
    if [[ "$remove" == "true" ]]; then
        echo ""
        echo -e "${BLUE}Removing containers...${NC}"
        for container in $containers; do
            remove_container "$container"
        done
    fi
    
    # Show summary
    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓ All services stopped successfully ($stopped/$total)${NC}"
        
        if [[ "$service_filter" == "all" || "$service_filter" == "" ]]; then
            echo ""
            echo -e "${BLUE}OnlyOffice DocSpace has been stopped${NC}"
            echo "Use 'onlyoffice-start' to start services again"
        fi
    else
        echo -e "${YELLOW}⚠ Some services failed to stop ($failed failures, $stopped stopped)${NC}"
        echo "Use 'onlyoffice-stop --force' to force stop remaining services"
        echo "Use 'onlyoffice-status' to check current status"
    fi
    
    # Show remaining running containers
    local remaining
    remaining=$(docker ps --format "{{.Names}}" | grep "^onlyoffice-" | wc -l)
    if [[ $remaining -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}$remaining OnlyOffice containers still running${NC}"
        echo "Use 'onlyoffice-status' for details"
    fi
}

# Main function
main() {
    local service_filter="" force="false" remove="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --graceful)
                force="false"  # default anyway
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --remove)
                remove="true"
                shift
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
    stop_services "$service_filter" "$force" "$remove"
}

# Run main function
main "$@"