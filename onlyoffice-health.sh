#!/bin/bash

# OnlyOffice DocSpace Health Check Script
# Phase 3: Complete Docker Abstraction - Container Health and Diagnostics
#
# This script provides comprehensive health checking of OnlyOffice services
# NO Docker knowledge required for administrators

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "OnlyOffice DocSpace Health Check"
    echo ""
    echo "Usage: onlyoffice-health [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  -v, --verbose           Show detailed health information"
    echo "  --web                   Test web accessibility"
    echo "  --fix                   Attempt to fix common issues"
    echo "  --summary               Show summary only"
    echo ""
    echo "Health Checks Performed:"
    echo "  • Container status and health"
    echo "  • Service dependencies"
    echo "  • Web server accessibility"
    echo "  • Database connectivity"
    echo "  • Storage accessibility"
    echo "  • Resource usage"
    echo ""
    echo "Examples:"
    echo "  onlyoffice-health                # Basic health check"
    echo "  onlyoffice-health -v             # Detailed health check"
    echo "  onlyoffice-health --web          # Include web accessibility test"
    echo "  onlyoffice-health --fix          # Attempt to fix issues found"
}

# Function to check container health
check_container_health() {
    local verbose="$1"
    local total=0 running=0 healthy=0 unhealthy=0 starting=0
    
    echo -e "${BLUE}Container Health Status:${NC}"
    
    for container in $(docker ps -a --format "{{.Names}}" | grep "^onlyoffice-" | sort); do
        ((total++))
        
        local status health uptime
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
        uptime=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null | cut -d'T' -f1 || echo "unknown")
        
        local service_name="${container#onlyoffice-}"
        
        case "$status" in
            "running")
                ((running++))
                case "$health" in
                    "healthy")
                        ((healthy++))
                        if [[ "$verbose" == "true" ]]; then
                            echo -e "  ${GREEN}✓${NC} $service_name (healthy, started: $uptime)"
                        else
                            echo -e "  ${GREEN}✓${NC} $service_name"
                        fi
                        ;;
                    "unhealthy")
                        ((unhealthy++))
                        echo -e "  ${RED}✗${NC} $service_name (unhealthy)"
                        ;;
                    "starting")
                        ((starting++))
                        echo -e "  ${YELLOW}⏳${NC} $service_name (starting)"
                        ;;
                    *)
                        echo -e "  ${GREEN}✓${NC} $service_name (running, no health check)"
                        ;;
                esac
                ;;
            "exited")
                echo -e "  ${RED}✗${NC} $service_name (stopped)"
                ;;
            *)
                echo -e "  ${YELLOW}⚠${NC} $service_name ($status)"
                ;;
        esac
    done
    
    echo ""
    echo -e "${BLUE}Container Summary:${NC}"
    echo "  Total: $total"
    echo "  Running: $running"
    echo "  Healthy: $healthy"
    echo "  Unhealthy: $unhealthy"
    echo "  Starting: $starting"
    echo "  Stopped: $((total - running))"
    
    # Overall health assessment
    if [[ $unhealthy -gt 0 ]]; then
        echo -e "  Overall: ${RED}Unhealthy ($unhealthy issues)${NC}"
        return 1
    elif [[ $starting -gt 0 ]]; then
        echo -e "  Overall: ${YELLOW}Starting ($starting services)${NC}"
        return 2
    elif [[ $running -eq $total && $healthy -gt 0 ]]; then
        echo -e "  Overall: ${GREEN}Healthy${NC}"
        return 0
    elif [[ $running -eq $total ]]; then
        echo -e "  Overall: ${GREEN}Running${NC}"
        return 0
    else
        echo -e "  Overall: ${RED}Issues Found${NC}"
        return 1
    fi
}

# Function to check web accessibility
check_web_access() {
    local verbose="$1"
    
    echo ""
    echo -e "${BLUE}Web Accessibility:${NC}"
    
    # Get host IP
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}' || echo "localhost")
    
    # Check if proxy is running
    if ! docker ps --format "{{.Names}}" | grep -q "^onlyoffice-proxy$"; then
        echo -e "  ${RED}✗${NC} Proxy not running - web access unavailable"
        return 1
    fi
    
    # Check HTTP access
    echo -e "  ${BLUE}Testing HTTP access...${NC}"
    if timeout 10 curl -s -f "http://$host_ip" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} HTTP accessible at http://$host_ip"
    else
        echo -e "  ${RED}✗${NC} HTTP not accessible at http://$host_ip"
    fi
    
    # Check HTTPS access (if SSL configured)
    local ssl_ports
    ssl_ports=$(docker port onlyoffice-proxy 2>/dev/null | grep "443" || echo "")
    if [[ -n "$ssl_ports" ]]; then
        echo -e "  ${BLUE}Testing HTTPS access...${NC}"
        if timeout 10 curl -s -f -k "https://$host_ip" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} HTTPS accessible at https://$host_ip"
        else
            echo -e "  ${RED}✗${NC} HTTPS not accessible at https://$host_ip"
        fi
    else
        echo -e "  ${YELLOW}ℹ${NC} HTTPS not configured"
    fi
    
    # Check internal routing
    if [[ "$verbose" == "true" ]]; then
        echo -e "  ${BLUE}Testing internal routing...${NC}"
        if docker exec onlyoffice-proxy curl -s -f http://onlyoffice-router:8092 >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Internal routing functional"
        else
            echo -e "  ${RED}✗${NC} Internal routing issues"
        fi
    fi
}

# Function to check database connectivity
check_database() {
    local verbose="$1"
    
    echo ""
    echo -e "${BLUE}Database Connectivity:${NC}"
    
    # Check if MySQL container is running
    if ! docker ps --format "{{.Names}}" | grep -q "^onlyoffice-mysql-server$"; then
        echo -e "  ${RED}✗${NC} MySQL server not running"
        return 1
    fi
    
    # Test database connection
    if docker exec onlyoffice-mysql-server mysqladmin ping -h localhost >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} MySQL server responding"
        
        if [[ "$verbose" == "true" ]]; then
            # Get database info
            local db_version uptime
            db_version=$(docker exec onlyoffice-mysql-server mysql --version 2>/dev/null | grep -o "Distrib [0-9.]*" || echo "unknown")
            uptime=$(docker exec onlyoffice-mysql-server mysqladmin status 2>/dev/null | grep -o "Uptime: [0-9]*" || echo "unknown")
            echo -e "  ${BLUE}ℹ${NC} Database: $db_version, $uptime seconds"
        fi
    else
        echo -e "  ${RED}✗${NC} MySQL server not responding"
        return 1
    fi
    
    # Test from application containers
    if docker exec onlyoffice-api curl -s http://onlyoffice-mysql-server:3306 >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Database accessible from application services"
    else
        echo -e "  ${YELLOW}⚠${NC} Database connectivity test from apps inconclusive"
    fi
}

# Function to check storage
check_storage() {
    local verbose="$1"
    
    echo ""
    echo -e "${BLUE}Storage Health:${NC}"
    
    # Check encrypted storage mount
    if mountpoint -q /mnt/docspace_data 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Encrypted storage mounted"
        
        local usage
        usage=$(df -h /mnt/docspace_data | awk 'NR==2{print $5}' | sed 's/%//')
        if [[ $usage -lt 80 ]]; then
            echo -e "  ${GREEN}✓${NC} Storage usage: ${usage}% (healthy)"
        elif [[ $usage -lt 90 ]]; then
            echo -e "  ${YELLOW}⚠${NC} Storage usage: ${usage}% (warning)"
        else
            echo -e "  ${RED}✗${NC} Storage usage: ${usage}% (critical)"
        fi
        
        if [[ "$verbose" == "true" ]]; then
            echo -e "  ${BLUE}ℹ${NC} Storage details:"
            df -h /mnt/docspace_data | tail -1 | awk '{print "    Size: " $2 ", Used: " $3 ", Available: " $4}'
        fi
    else
        echo -e "  ${RED}✗${NC} Encrypted storage not mounted"
        return 1
    fi
    
    # Test write access
    local test_file="/mnt/docspace_data/health_check_test.tmp"
    if echo "test" > "$test_file" 2>/dev/null && rm "$test_file" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Storage write access functional"
    else
        echo -e "  ${RED}✗${NC} Storage write access failed"
        return 1
    fi
}

# Function to check resource usage
check_resources() {
    local verbose="$1"
    
    echo ""
    echo -e "${BLUE}Resource Usage:${NC}"
    
    # Memory usage
    local mem_total mem_used mem_percent
    mem_total=$(free -m | awk 'NR==2{print $2}')
    mem_used=$(free -m | awk 'NR==2{print $3}')
    mem_percent=$((mem_used * 100 / mem_total))
    
    if [[ $mem_percent -lt 80 ]]; then
        echo -e "  ${GREEN}✓${NC} Memory usage: ${mem_percent}% (${mem_used}M/${mem_total}M)"
    elif [[ $mem_percent -lt 90 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Memory usage: ${mem_percent}% (${mem_used}M/${mem_total}M)"
    else
        echo -e "  ${RED}✗${NC} Memory usage: ${mem_percent}% (${mem_used}M/${mem_total}M)"
    fi
    
    # Disk usage
    local disk_usage
    disk_usage=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
    
    if [[ $disk_usage -lt 80 ]]; then
        echo -e "  ${GREEN}✓${NC} Root disk usage: ${disk_usage}%"
    elif [[ $disk_usage -lt 90 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Root disk usage: ${disk_usage}%"
    else
        echo -e "  ${RED}✗${NC} Root disk usage: ${disk_usage}%"
    fi
    
    # Load average
    if [[ "$verbose" == "true" ]]; then
        local load_avg
        load_avg=$(uptime | grep -o "load average: .*" | cut -d: -f2)
        echo -e "  ${BLUE}ℹ${NC} System load:$load_avg"
    fi
}

# Function to attempt fixes for common issues
attempt_fixes() {
    echo ""
    echo -e "${BLUE}Attempting to fix common issues...${NC}"
    
    local fixes_applied=0
    
    # Fix 1: Restart unhealthy containers
    local unhealthy_containers
    unhealthy_containers=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | grep "^onlyoffice-" || true)
    
    if [[ -n "$unhealthy_containers" ]]; then
        echo -e "  ${YELLOW}Restarting unhealthy containers...${NC}"
        for container in $unhealthy_containers; do
            echo -e "    Restarting $container"
            docker restart "$container" >/dev/null 2>&1 || true
            ((fixes_applied++))
        done
    fi
    
    # Fix 2: Ensure network exists
    if ! docker network ls --format "{{.Name}}" | grep -q "^onlyoffice$"; then
        echo -e "  ${YELLOW}Creating missing OnlyOffice network...${NC}"
        docker network create onlyoffice >/dev/null 2>&1 || true
        ((fixes_applied++))
    fi
    
    # Fix 3: Clean up stopped containers
    local stopped_containers
    stopped_containers=$(docker ps -a --filter "status=exited" --format "{{.Names}}" | grep "^onlyoffice-" || true)
    
    if [[ -n "$stopped_containers" ]]; then
        echo -e "  ${YELLOW}Cleaning up stopped containers...${NC}"
        docker rm $stopped_containers >/dev/null 2>&1 || true
        ((fixes_applied++))
    fi
    
    if [[ $fixes_applied -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} No automatic fixes needed"
    else
        echo -e "  ${GREEN}✓${NC} Applied $fixes_applied automatic fixes"
        echo -e "  ${BLUE}ℹ${NC} Wait 30 seconds and run health check again"
    fi
}

# Main function
main() {
    local verbose="false" web_check="false" attempt_fix="false" summary_only="false"
    
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
            --web)
                web_check="true"
                shift
                ;;
            --fix)
                attempt_fix="true"
                shift
                ;;
            --summary)
                summary_only="true"
                shift
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}"
                show_help
                exit 1
                ;;
            *)
                echo -e "${RED}Error: Unexpected argument $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo -e "${BLUE}OnlyOffice DocSpace Health Check${NC}"
    echo "$(date)"
    echo ""
    
    local overall_health=0
    
    # Run health checks
    check_container_health "$verbose" || overall_health=$?
    
    if [[ "$summary_only" != "true" ]]; then
        check_storage "$verbose" || true
        check_database "$verbose" || true
        
        if [[ "$web_check" == "true" ]]; then
            check_web_access "$verbose" || true
        fi
        
        check_resources "$verbose" || true
    fi
    
    # Attempt fixes if requested
    if [[ "$attempt_fix" == "true" ]]; then
        attempt_fixes
    fi
    
    # Final summary
    echo ""
    echo -e "${BLUE}Health Check Summary:${NC}"
    case $overall_health in
        0)
            echo -e "  ${GREEN}✓ OnlyOffice DocSpace is healthy${NC}"
            ;;
        1)
            echo -e "  ${RED}✗ OnlyOffice DocSpace has health issues${NC}"
            echo "  Run 'onlyoffice-health --fix' to attempt automatic fixes"
            ;;
        2)
            echo -e "  ${YELLOW}⏳ OnlyOffice DocSpace is starting up${NC}"
            echo "  Wait a few minutes and check again"
            ;;
    esac
    
    exit $overall_health
}

# Run main function
main "$@"