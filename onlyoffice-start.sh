#!/bin/bash

# OnlyOffice DocSpace Start Management Script
# Phase 3: Complete Docker Abstraction - Container Lifecycle Management
#
# This script starts OnlyOffice services with proper dependency ordering
# NO Docker knowledge required for administrators

set -e

COMPOSE_DIR="/app/onlyoffice"
COMPOSE_FILES="-f $COMPOSE_DIR/docspace.yml -f $COMPOSE_DIR/db.yml -f $COMPOSE_DIR/ds.yml -f $COMPOSE_DIR/proxy.yml"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "OnlyOffice DocSpace Start Management"
    echo ""
    echo "Usage: onlyoffice-start [OPTIONS] [SERVICE]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  -f, --force             Force start (stop and restart if running)"
    echo "  --ssl                   Start with SSL configuration"
    echo ""
    echo "Service Groups:"
    echo "  all                     Start all services (default)"
    echo "  infrastructure          Start core services (mysql, proxy, router)"
    echo "  api                     Start API services"
    echo "  frontend                Start frontend services"
    echo "  backend                 Start backend services"
    echo ""
    echo "Individual Services:"
    echo "  mysql-server            Database service"
    echo "  proxy                   Web proxy service"
    echo "  router                  Internal router service"
    echo "  document-server         Document server service"
    echo "  [service-name]          Any specific OnlyOffice service"
    echo ""
    echo "Examples:"
    echo "  onlyoffice-start                    # Start all services"
    echo "  onlyoffice-start infrastructure    # Start core services only"
    echo "  onlyoffice-start mysql-server      # Start database only"
    echo "  onlyoffice-start --ssl              # Start with SSL enabled"
}

# Function to check prerequisites
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
    
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
}

# Function to ensure required network exists
ensure_network() {
    local network_name="onlyoffice"
    
    if ! docker network ls --format "{{.Name}}" | grep -q "^${network_name}$"; then
        echo -e "${YELLOW}Creating OnlyOffice network...${NC}"
        docker network create "$network_name"
        echo -e "${GREEN}✓ Network created${NC}"
    else
        echo -e "${GREEN}✓ OnlyOffice network exists${NC}"
    fi
}

# Function to start services with dependency management
start_services() {
    local service_filter="$1"
    local use_ssl="$2"
    local force="$3"
    
    echo -e "${BLUE}Starting OnlyOffice DocSpace Services${NC}"
    echo "$(date)"
    echo ""
    
    # Ensure network exists
    ensure_network
    
    # Determine compose files to use
    local compose_cmd="docker compose $COMPOSE_FILES"
    if [[ "$use_ssl" == "true" ]]; then
        compose_cmd="docker compose $COMPOSE_FILES -f $COMPOSE_DIR/proxy-ssl.yml"
        echo -e "${BLUE}Using SSL configuration${NC}"
    fi
    
    # Handle force restart
    if [[ "$force" == "true" ]]; then
        echo -e "${YELLOW}Force restart requested - stopping services first...${NC}"
        $compose_cmd down --remove-orphans || true
        echo ""
    fi
    
    case "$service_filter" in
        "all"|"")
            echo -e "${BLUE}Starting all OnlyOffice services...${NC}"
            $compose_cmd up -d
            ;;
        "infrastructure")
            echo -e "${BLUE}Starting infrastructure services...${NC}"
            # Start in dependency order: mysql -> document-server -> proxy -> router
            docker compose -f $COMPOSE_DIR/db.yml up -d
            sleep 5
            docker compose -f $COMPOSE_DIR/ds.yml up -d  
            sleep 3
            if [[ "$use_ssl" == "true" ]]; then
                docker compose -f $COMPOSE_DIR/proxy-ssl.yml up -d
            else
                docker compose -f $COMPOSE_DIR/proxy.yml up -d
            fi
            ;;
        "mysql-server")
            echo -e "${BLUE}Starting MySQL database service...${NC}"
            docker compose -f $COMPOSE_DIR/db.yml up -d
            ;;
        "document-server")
            echo -e "${BLUE}Starting Document Server...${NC}"
            docker compose -f $COMPOSE_DIR/ds.yml up -d
            ;;
        "proxy")
            echo -e "${BLUE}Starting proxy service...${NC}"
            if [[ "$use_ssl" == "true" ]]; then
                docker compose -f $COMPOSE_DIR/proxy-ssl.yml up -d
            else
                docker compose -f $COMPOSE_DIR/proxy.yml up -d
            fi
            ;;
        *)
            # Try to start specific service
            echo -e "${BLUE}Starting service: $service_filter${NC}"
            # Find which compose file contains the service
            local service_found=false
            for compose_file in docspace.yml db.yml ds.yml proxy.yml; do
                if grep -q "$service_filter" "$COMPOSE_DIR/$compose_file" 2>/dev/null; then
                    docker compose -f "$COMPOSE_DIR/$compose_file" up -d "$service_filter" || docker compose -f "$COMPOSE_DIR/$compose_file" up -d "onlyoffice-$service_filter"
                    service_found=true
                    break
                fi
            done
            
            if [[ "$service_found" == "false" ]]; then
                echo -e "${RED}Error: Service '$service_filter' not found${NC}"
                echo "Use 'onlyoffice-start --help' to see available services"
                exit 1
            fi
            ;;
    esac
    
    echo ""
    echo -e "${YELLOW}Waiting for services to start...${NC}"
    sleep 10
    
    # Show startup status
    echo -e "${BLUE}Service Status:${NC}"
    local started=0 total=0
    
    for container in $(docker ps -a --format "{{.Names}}" | grep "^onlyoffice-" | head -10); do
        ((total++))
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "running" ]]; then
            echo -e "  ${GREEN}✓${NC} ${container#onlyoffice-}"
            ((started++))
        else
            echo -e "  ${RED}✗${NC} ${container#onlyoffice-} ($status)"
        fi
    done
    
    echo ""
    if [[ $started -eq $total ]]; then
        echo -e "${GREEN}✓ All services started successfully ($started/$total)${NC}"
        echo ""
        echo -e "${BLUE}OnlyOffice DocSpace is now running${NC}"
        local host_ip
        host_ip=$(hostname -I | awk '{print $1}' || echo "localhost")
        if [[ "$use_ssl" == "true" ]]; then
            echo "Access URL: https://$host_ip"
        else
            echo "Access URL: http://$host_ip"
        fi
    else
        echo -e "${YELLOW}⚠ Some services may still be starting ($started/$total running)${NC}"
        echo "Use 'onlyoffice-status' to check detailed status"
        echo "Use 'onlyoffice-logs <service>' to view logs if issues persist"
    fi
}

# Main function
main() {
    local service_filter="" use_ssl="false" force="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            --ssl)
                use_ssl="true"
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
    start_services "$service_filter" "$use_ssl" "$force"
}

# Run main function
main "$@"