#!/bin/bash

# OnlyOffice DocSpace Status Management Script
# Phase 3: Complete Docker Abstraction - Container Status Management
#
# This script provides human-readable status of OnlyOffice services
# NO Docker knowledge required for administrators

set -e

COMPOSE_DIR="/app/onlyoffice"
SCRIPT_NAME="onlyoffice-status"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show help
show_help() {
    echo "OnlyOffice DocSpace Status Management"
    echo ""
    echo "Usage: $SCRIPT_NAME [OPTIONS] [SERVICE]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help"
    echo "  -v, --verbose       Show detailed service information"
    echo "  -q, --quiet         Show only service names and status"
    echo "  --raw               Show raw status (for scripting)"
    echo ""
    echo "Service Names (optional):"
    echo "  api                 API services (api, api-system, sdk)"
    echo "  frontend            Frontend services (studio, login, files, etc.)"
    echo "  backend             Backend services (people, backup, ssoauth, etc.)"
    echo "  infrastructure      Core services (proxy, router, mysql, document-server)"
    echo "  [specific-name]     Individual service (e.g., studio, mysql-server)"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME                    # Show status of all services"
    echo "  $SCRIPT_NAME api               # Show status of API services only"
    echo "  $SCRIPT_NAME studio            # Show status of studio service"
    echo "  $SCRIPT_NAME -v                # Show detailed status"
    echo "  $SCRIPT_NAME --raw             # Machine-readable output"
}

# Function to check if OnlyOffice is installed
check_installation() {
    if [[ ! -d "$COMPOSE_DIR" ]]; then
        echo -e "${RED}Error: OnlyOffice DocSpace not found at $COMPOSE_DIR${NC}"
        echo "Please install OnlyOffice DocSpace first."
        exit 1
    fi
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker not found${NC}"
        echo "OnlyOffice DocSpace requires Docker to be installed."
        exit 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker Compose not found${NC}"
        echo "OnlyOffice DocSpace requires Docker Compose to be installed."
        exit 1
    fi
}

# Function to get container status with human-readable output
get_container_status() {
    local container_name="$1"
    local verbose="$2"
    
    # Check if container exists
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        if [[ "$verbose" == "true" ]]; then
            echo -e "${RED}Not Installed${NC}"
        else
            echo -e "${RED}Not Found${NC}"
        fi
        return
    fi
    
    # Get container info
    local status health created ports
    status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
    health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
    
    if [[ "$verbose" == "true" ]]; then
        created=$(docker inspect --format='{{.Created}}' "$container_name" 2>/dev/null | cut -d'T' -f1 || echo "unknown")
        ports=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} {{end}}{{end}}' "$container_name" 2>/dev/null || echo "none")
    fi
    
    # Format status with colors
    case "$status" in
        "running")
            if [[ "$health" == "healthy" ]]; then
                status_display="${GREEN}Running (Healthy)${NC}"
            elif [[ "$health" == "unhealthy" ]]; then
                status_display="${YELLOW}Running (Unhealthy)${NC}"
            elif [[ "$health" == "starting" ]]; then
                status_display="${YELLOW}Starting${NC}"
            else
                status_display="${GREEN}Running${NC}"
            fi
            ;;
        "exited")
            status_display="${RED}Stopped${NC}"
            ;;
        "restarting")
            status_display="${YELLOW}Restarting${NC}"
            ;;
        "paused")
            status_display="${YELLOW}Paused${NC}"
            ;;
        *)
            status_display="${RED}$status${NC}"
            ;;
    esac
    
    if [[ "$verbose" == "true" ]]; then
        echo -e "$status_display (Created: $created, Ports: ${ports:-none})"
    else
        echo -e "$status_display"
    fi
}

# Function to get service category containers
get_service_containers() {
    local category="$1"
    
    case "$category" in
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
            if docker ps -a --format "{{.Names}}" | grep -q "^onlyoffice-${category}$"; then
                echo "onlyoffice-${category}"
            elif docker ps -a --format "{{.Names}}" | grep -q "^${category}$"; then
                echo "$category"
            else
                echo ""
            fi
            ;;
    esac
}

# Function to show service status
show_service_status() {
    local service_filter="$1"
    local verbose="$2"
    local quiet="$3"
    local raw="$4"
    
    # Get containers to check
    local containers
    if [[ -z "$service_filter" ]]; then
        containers=$(get_service_containers "all")
    else
        containers=$(get_service_containers "$service_filter")
        if [[ -z "$containers" ]]; then
            echo -e "${RED}Error: Unknown service '$service_filter'${NC}"
            echo "Use --help to see available services"
            exit 1
        fi
    fi
    
    # Show header unless quiet or raw mode
    if [[ "$quiet" != "true" && "$raw" != "true" ]]; then
        if [[ -z "$service_filter" ]]; then
            echo -e "${BLUE}OnlyOffice DocSpace - Service Status${NC}"
        else
            echo -e "${BLUE}OnlyOffice DocSpace - ${service_filter^} Services${NC}"
        fi
        echo "$(date)"
        echo ""
    fi
    
    # Track statistics
    local total=0 running=0 healthy=0 stopped=0
    
    # Process each container
    for container in $containers; do
        ((total++))
        
        # Get status
        local status_output
        status_output=$(get_container_status "$container" "$verbose")
        
        # Count statuses for summary
        if echo "$status_output" | grep -q "Running"; then
            ((running++))
            if echo "$status_output" | grep -q "Healthy"; then
                ((healthy++))
            fi
        elif echo "$status_output" | grep -q "Stopped\|Not Found"; then
            ((stopped++))
        fi
        
        # Format output
        local service_name="${container#onlyoffice-}"
        
        if [[ "$raw" == "true" ]]; then
            # Machine-readable output
            local raw_status
            raw_status=$(echo "$status_output" | sed -e 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')
            echo "$service_name:$raw_status"
        elif [[ "$quiet" == "true" ]]; then
            printf "%-25s %s\n" "$service_name" "$status_output"
        else
            printf "%-25s %s\n" "$service_name" "$status_output"
        fi
    done
    
    # Show summary unless quiet or raw mode
    if [[ "$quiet" != "true" && "$raw" != "true" ]]; then
        echo ""
        echo -e "${BLUE}Summary:${NC}"
        echo "  Total Services: $total"
        echo "  Running: $running"
        echo "  Healthy: $healthy" 
        echo "  Stopped: $stopped"
        
        # Overall status
        if [[ $running -eq $total && $healthy -eq $running ]]; then
            echo -e "  Overall Status: ${GREEN}All Services Healthy${NC}"
        elif [[ $running -eq $total ]]; then
            echo -e "  Overall Status: ${YELLOW}All Services Running (Some Unhealthy)${NC}"
        elif [[ $running -gt 0 ]]; then
            echo -e "  Overall Status: ${YELLOW}Partially Running${NC}"
        else
            echo -e "  Overall Status: ${RED}All Services Stopped${NC}"
        fi
        
        echo ""
        echo "Use 'onlyoffice-logs <service>' to view logs"
        echo "Use 'onlyoffice-start' to start stopped services"
        echo "Use 'onlyoffice-restart <service>' to restart unhealthy services"
    fi
}

# Main function
main() {
    local service_filter="" verbose="false" quiet="false" raw="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -q|--quiet)
                quiet="true"
                shift
                ;;
            --raw)
                raw="true"
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
    
    check_installation
    show_service_status "$service_filter" "$verbose" "$quiet" "$raw"
}

# Run main function
main "$@"