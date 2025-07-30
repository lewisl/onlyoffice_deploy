#!/bin/bash

# OnlyOffice DocSpace Logs Management Script
# Phase 3: Complete Docker Abstraction - Container Health and Diagnostics
#
# This script provides easy access to OnlyOffice service logs
# NO Docker knowledge required for administrators

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "OnlyOffice DocSpace Logs Management"
    echo ""
    echo "Usage: onlyoffice-logs [OPTIONS] [SERVICE]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  -f, --follow            Follow log output (like tail -f)"
    echo "  -n, --lines NUMBER      Number of lines to show (default: 100)"
    echo "  --since TIMESTAMP       Show logs since timestamp (e.g., '2h', '30m', '2023-01-01')"
    echo "  --until TIMESTAMP       Show logs until timestamp"
    echo "  -t, --timestamps        Show timestamps"
    echo "  --all                   Show logs from all services"
    echo ""
    echo "Service Groups:"
    echo "  api                     API services logs"
    echo "  frontend                Frontend services logs"
    echo "  backend                 Backend services logs"
    echo "  infrastructure          Core services logs"
    echo ""
    echo "Individual Services:"
    echo "  mysql-server            Database logs"
    echo "  proxy                   Web proxy logs"
    echo "  router                  Internal router logs"
    echo "  document-server         Document server logs"
    echo "  studio                  Studio interface logs"
    echo "  files                   File management logs"
    echo "  api                     API service logs"
    echo "  [service-name]          Any OnlyOffice service"
    echo ""
    echo "Examples:"
    echo "  onlyoffice-logs proxy               # Show proxy logs"
    echo "  onlyoffice-logs -f studio           # Follow studio logs"
    echo "  onlyoffice-logs -n 50 mysql-server  # Show last 50 database log lines"
    echo "  onlyoffice-logs --since 1h api      # Show API logs from last hour"
    echo "  onlyoffice-logs --all                # Show recent logs from all services"
}

# Function to get service containers
get_service_containers() {
    local service_filter="$1"
    
    case "$service_filter" in
        "api")
            echo "onlyoffice-api onlyoffice-api-system onlyoffice-sdk"
            ;;
        "frontend")  
            echo "onlyoffice-studio onlyoffice-login onlyoffice-files onlyoffice-files-services onlyoffice-doceditor onlyoffice-socket onlyoffice-studio-notify"
            ;;
        "backend")
            echo "onlyoffice-people-server onlyoffice-backup onlyoffice-backup-background-tasks onlyoffice-ssoauth onlyoffice-clear-events"
            ;;
        "infrastructure")
            echo "onlyoffice-proxy onlyoffice-router onlyoffice-mysql-server onlyoffice-document-server"
            ;;
        "all")
            get_service_containers "api"
            get_service_containers "frontend" 
            get_service_containers "backend"
            get_service_containers "infrastructure"
            ;;
        *)
            # Check if it's a specific container name
            if docker ps -a --format "{{.Names}}" | grep -q "^onlyoffice-${service_filter}$"; then
                echo "onlyoffice-${service_filter}"
            elif docker ps -a --format "{{.Names}}" | grep -q "^${service_filter}$"; then
                echo "$service_filter"
            else
                echo ""
            fi
            ;;
    esac
}

# Function to show logs for a single container
show_container_logs() {
    local container="$1"
    local follow="$2"
    local lines="$3"
    local since="$4"
    local until="$5"
    local timestamps="$6"
    local show_multiple="$7"
    
    # Check if container exists
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        echo -e "${RED}✗${NC} Service '${container#onlyoffice-}' not found"
        return 1
    fi
    
    # Build docker logs command
    local logs_cmd="docker logs"
    
    if [[ "$follow" == "true" ]]; then
        logs_cmd="$logs_cmd -f"
    fi
    
    if [[ -n "$lines" ]]; then
        logs_cmd="$logs_cmd --tail $lines"
    fi
    
    if [[ -n "$since" ]]; then
        logs_cmd="$logs_cmd --since $since"
    fi
    
    if [[ -n "$until" ]]; then
        logs_cmd="$logs_cmd --until $until"
    fi
    
    if [[ "$timestamps" == "true" ]]; then
        logs_cmd="$logs_cmd -t"
    fi
    
    logs_cmd="$logs_cmd $container"
    
    # Show header if displaying multiple services
    if [[ "$show_multiple" == "true" ]]; then
        echo -e "${BLUE}=== ${container#onlyoffice-} ===${NC}"
    fi
    
    # Execute logs command
    eval "$logs_cmd" 2>/dev/null || {
        echo -e "${RED}✗${NC} Unable to retrieve logs for ${container#onlyoffice-}"
        return 1
    }
    
    if [[ "$show_multiple" == "true" ]]; then
        echo ""
    fi
}

# Function to show aggregated logs
show_aggregated_logs() {
    local containers="$1"
    local follow="$2"
    local lines="$3"
    local since="$4"
    local until="$5"
    local timestamps="$6"
    
    echo -e "${BLUE}Aggregated logs from multiple services:${NC}"
    echo -e "${YELLOW}Note: Logs are shown sequentially, not chronologically mixed${NC}"
    echo ""
    
    local container_count=0
    for container in $containers; do
        ((container_count++))
    done
    
    if [[ $container_count -gt 10 ]]; then
        echo -e "${YELLOW}Warning: Showing logs from $container_count services - output may be very long${NC}"
        echo "Press Ctrl+C to stop if needed"
        echo ""
        sleep 2
    fi
    
    for container in $containers; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            show_container_logs "$container" "false" "$lines" "$since" "$until" "$timestamps" "true"
        fi
    done
}

# Function to validate numeric argument
validate_number() {
    local value="$1"
    local name="$2"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: $name must be a number${NC}"
        exit 1
    fi
}

# Main function
main() {
    local service_filter="" follow="false" lines="100" since="" until="" timestamps="false" show_all="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--follow)
                follow="true"
                shift
                ;;
            -n|--lines)
                if [[ -n "$2" ]]; then
                    validate_number "$2" "lines"
                    lines="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --lines requires a number${NC}"
                    exit 1
                fi
                ;;
            --since)
                if [[ -n "$2" ]]; then
                    since="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --since requires a timestamp${NC}"
                    exit 1
                fi
                ;;
            --until)
                if [[ -n "$2" ]]; then
                    until="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --until requires a timestamp${NC}"
                    exit 1
                fi
                ;;
            -t|--timestamps)
                timestamps="true"
                shift
                ;;
            --all)
                show_all="true"
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
    
    # Handle --all flag
    if [[ "$show_all" == "true" ]]; then
        if [[ -n "$service_filter" ]]; then
            echo -e "${RED}Error: Cannot use --all with specific service${NC}"
            exit 1
        fi
        service_filter="all"
    fi
    
    # Default to showing available services if no service specified
    if [[ -z "$service_filter" ]]; then
        echo -e "${BLUE}OnlyOffice DocSpace - Available Services for Log Viewing:${NC}"
        echo ""
        
        local available_services=()
        for container in $(docker ps --format "{{.Names}}" | grep "^onlyoffice-" | sort); do
            available_services+=("${container#onlyoffice-}")
        done
        
        if [[ ${#available_services[@]} -eq 0 ]]; then
            echo -e "${RED}No OnlyOffice services are currently running${NC}"
            echo "Use 'onlyoffice-start' to start services first"
            exit 1
        fi
        
        echo "Running services:"
        for service in "${available_services[@]}"; do
            echo "  • $service"
        done
        
        echo ""
        echo "Usage examples:"
        echo "  onlyoffice-logs proxy           # View proxy logs"
        echo "  onlyoffice-logs -f studio       # Follow studio logs"
        echo "  onlyoffice-logs --all           # View all service logs"
        echo ""
        echo "Use 'onlyoffice-logs --help' for more options"
        exit 0
    fi
    
    # Get containers for the service filter
    local containers
    containers=$(get_service_containers "$service_filter")
    
    if [[ -z "$containers" ]]; then
        echo -e "${RED}Error: Unknown service '$service_filter'${NC}"
        echo "Use 'onlyoffice-logs' without arguments to see available services"
        exit 1
    fi
    
    # Count containers
    local container_count=0
    for container in $containers; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            ((container_count++))
        fi
    done
    
    if [[ $container_count -eq 0 ]]; then
        echo -e "${RED}No containers found for service '$service_filter'${NC}"
        echo "Use 'onlyoffice-status' to check service status"
        exit 1
    fi
    
    # Show logs
    if [[ $container_count -eq 1 ]]; then
        # Single container - show logs directly
        local container
        container=$(echo $containers | awk '{print $1}')
        echo -e "${BLUE}Showing logs for: ${container#onlyoffice-}${NC}"
        echo ""
        show_container_logs "$container" "$follow" "$lines" "$since" "$until" "$timestamps" "false"
    else
        # Multiple containers
        if [[ "$follow" == "true" ]]; then
            echo -e "${RED}Error: Cannot follow logs from multiple services${NC}"
            echo "Specify a single service to use --follow"
            exit 1
        fi
        
        show_aggregated_logs "$containers" "$follow" "$lines" "$since" "$until" "$timestamps"
    fi
}

# Run main function
main "$@"