#!/bin/bash

# OnlyOffice DocSpace Execute Commands Script
# Phase 3: Complete Docker Abstraction - Container Diagnostics
#
# This script allows executing commands within OnlyOffice containers
# NO Docker knowledge required for administrators

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "OnlyOffice DocSpace Execute Commands"
    echo ""
    echo "Usage: onlyoffice-exec [OPTIONS] SERVICE COMMAND"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  -i, --interactive       Interactive mode (allocate TTY)"
    echo "  --user USER             Run as specific user (default: root)"
    echo "  --workdir PATH          Set working directory"
    echo ""
    echo "Available Services:"
    echo "  mysql-server            Database service"
    echo "  proxy                   Web proxy service"
    echo "  router                  Internal router service"
    echo "  document-server         Document server service"
    echo "  studio                  Studio interface service"
    echo "  files                   File management service"
    echo "  api                     API service"
    echo "  [service-name]          Any OnlyOffice service"
    echo ""
    echo "Common Commands:"
    echo "  bash                    Open interactive shell"
    echo "  sh                      Open basic shell"
    echo "  ls -la                  List files"
    echo "  ps aux                  List processes"
    echo "  cat /etc/issue          Show OS version"
    echo "  df -h                   Show disk usage"
    echo "  free -h                 Show memory usage"
    echo ""
    echo "Service-Specific Commands:"
    echo "  mysql-server:"
    echo "    mysql -u root -p      Connect to MySQL"
    echo "    mysqladmin status     Show MySQL status"
    echo ""
    echo "  proxy:"
    echo "    nginx -t              Test nginx configuration"
    echo "    nginx -s reload       Reload nginx configuration"
    echo ""
    echo "Examples:"
    echo "  onlyoffice-exec proxy nginx -t                    # Test nginx config"
    echo "  onlyoffice-exec -i mysql-server bash              # Interactive shell in database"
    echo "  onlyoffice-exec studio ls -la /app/onlyoffice     # List app directory"
    echo "  onlyoffice-exec api cat /proc/cpuinfo             # Show CPU info"
}

# Function to get full container name
get_container_name() {
    local service="$1"
    
    # Check if it's already a full container name
    if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
        echo "$service"
        return 0
    fi
    
    # Try with onlyoffice- prefix
    local full_name="onlyoffice-${service}"
    if docker ps --format "{{.Names}}" | grep -q "^${full_name}$"; then
        echo "$full_name"
        return 0
    fi
    
    return 1
}

# Function to check if container is running
check_container_running() {
    local container="$1"
    
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        return 1
    fi
    
    return 0
}

# Function to execute command in container
execute_command() {
    local service="$1"
    local command="$2"
    local interactive="$3"
    local user="$4"
    local workdir="$5"
    
    # Get full container name
    local container
    if ! container=$(get_container_name "$service"); then
        echo -e "${RED}Error: Service '$service' not found${NC}"
        echo ""
        echo "Available services:"
        docker ps --format "{{.Names}}" | grep "^onlyoffice-" | sed 's/onlyoffice-/  • /' | sort
        return 1
    fi
    
    # Check if container is running
    if ! check_container_running "$container"; then
        echo -e "${RED}Error: Service '${service}' is not running${NC}"
        echo "Use 'onlyoffice-status' to check service status"
        echo "Use 'onlyoffice-start ${service}' to start the service"
        return 1
    fi
    
    # Build docker exec command
    local exec_cmd="docker exec"
    
    if [[ "$interactive" == "true" ]]; then
        exec_cmd="$exec_cmd -it"
    fi
    
    if [[ -n "$user" ]]; then
        exec_cmd="$exec_cmd --user $user" 
    fi
    
    if [[ -n "$workdir" ]]; then
        exec_cmd="$exec_cmd --workdir $workdir"
    fi
    
    exec_cmd="$exec_cmd $container $command"
    
    # Show what we're executing
    echo -e "${BLUE}Executing in service '${service}':${NC} $command"
    echo ""
    
    # Execute the command
    eval "$exec_cmd"
}

# Function to show service information
show_service_info() {
    local service="$1"
    
    local container
    if ! container=$(get_container_name "$service"); then
        echo -e "${RED}Error: Service '$service' not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Service Information: ${service}${NC}"
    echo ""
    
    # Container details
    local status health image
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
    health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null || echo "unknown")
    
    echo "Container: $container"
    echo "Status: $status"
    echo "Health: $health"
    echo "Image: $image"
    echo ""
    
    if [[ "$status" == "running" ]]; then
        echo -e "${GREEN}✓ Service is running and ready for commands${NC}"
    else
        echo -e "${RED}✗ Service is not running${NC}"
        echo "Use 'onlyoffice-start ${service}' to start the service"
    fi
}

# Function to suggest commands based on service type
suggest_commands() {
    local service="$1"
    
    echo -e "${BLUE}Suggested commands for '${service}':${NC}"
    echo ""
    
    case "$service" in
        "mysql-server")
            echo "  mysql -u root -p                    # Connect to MySQL"
            echo "  mysqladmin status                   # Show MySQL status"
            echo "  mysql -e 'SHOW DATABASES;'         # List databases"
            echo "  cat /etc/mysql/my.cnf               # Show MySQL config"
            ;;
        "proxy")
            echo "  nginx -t                            # Test configuration"
            echo "  nginx -s reload                     # Reload configuration"
            echo "  cat /etc/nginx/nginx.conf           # Show nginx config"
            echo "  ls /var/log/nginx/                  # List log files"
            ;;
        "document-server")
            echo "  supervisorctl status                # Show services status"
            echo "  cat /etc/onlyoffice/documentserver/local.json"
            echo "  ls /var/www/onlyoffice/             # List document server files"
            ;;
        "router"|"api"|"studio"|"files")
            echo "  ps aux                              # List processes" 
            echo "  ls /app/onlyoffice/                 # List application files"
            echo "  cat /proc/meminfo                   # Show memory info"
            echo "  netstat -tlnp                       # Show listening ports"
            ;;
        *)
            echo "  bash                                # Interactive shell"
            echo "  ps aux                              # List processes"
            echo "  ls -la                              # List files"
            echo "  cat /etc/issue                      # Show OS version"
            echo "  df -h                               # Show disk usage"
            ;;
    esac
    
    echo ""
    echo "General commands:"
    echo "  bash                                # Interactive shell"
    echo "  top                                 # System monitor"
    echo "  env                                 # Environment variables"
}

# Main function
main() {
    local service="" command="" interactive="false" user="" workdir=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--interactive)
                interactive="true"
                shift
                ;;
            --user)
                if [[ -n "$2" ]]; then
                    user="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --user requires a username${NC}"
                    exit 1
                fi
                ;;
            --workdir)
                if [[ -n "$2" ]]; then
                    workdir="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --workdir requires a path${NC}"
                    exit 1
                fi
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$service" ]]; then
                    service="$1"
                    shift
                elif [[ -z "$command" ]]; then
                    # Rest of arguments are the command
                    command="$*"
                    break
                fi
                ;;
        esac
    done
    
    # Show available services if no service specified
    if [[ -z "$service" ]]; then
        echo -e "${BLUE}OnlyOffice DocSpace - Available Services:${NC}"
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
        for service_name in "${available_services[@]}"; do
            echo "  • $service_name"
        done
        
        echo ""
        echo "Usage: onlyoffice-exec SERVICE COMMAND"
        echo "Example: onlyoffice-exec proxy nginx -t"
        echo ""
        echo "Use 'onlyoffice-exec --help' for more information"
        exit 0
    fi
    
    # Show service info and suggestions if no command specified
    if [[ -z "$command" ]]; then
        show_service_info "$service"
        echo ""
        suggest_commands "$service"
        exit 0
    fi
    
    # Execute the command
    execute_command "$service" "$command" "$interactive" "$user" "$workdir"
}

# Run main function
main "$@"