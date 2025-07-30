#!/bin/bash

# OnlyOffice DocSpace Complete Uninstall Script
# This script completely removes OnlyOffice DocSpace from the system
# Based on actual steps required for clean removal

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ONLYOFFICE_DIR="/app/onlyoffice"
ENCRYPTED_STORAGE="/mnt/docspace_data"

show_help() {
    echo "OnlyOffice DocSpace Complete Uninstall"
    echo ""
    echo "Usage: onlyoffice-uninstall [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help"
    echo "  --force                 Skip confirmation prompts"
    echo "  --keep-data             Keep data in encrypted storage"
    echo "  --keep-storage          Keep encrypted storage directories (preserve structure)"
    echo "  --dry-run               Show what would be removed without actually removing"
    echo ""
    echo "What will be removed:"
    echo "  • All OnlyOffice Docker containers (stopped and removed)"
    echo "  • All OnlyOffice Docker volumes"
    echo "  • OnlyOffice Docker network"
    echo "  • OnlyOffice installation directory (/app/onlyoffice)"
    echo "  • OnlyOffice data in encrypted storage (unless --keep-data)"
    echo ""
    echo "What will be preserved:"
    echo "  • Encrypted storage mount point (/mnt/docspace_data)"
    echo "  • System Docker installation"
    echo "  • OnlyOffice deployment toolkit scripts"
    echo ""
    echo "Examples:"
    echo "  onlyoffice-uninstall                    # Interactive uninstall"
    echo "  onlyoffice-uninstall --force            # Uninstall without prompts"
    echo "  onlyoffice-uninstall --keep-data        # Remove app but keep data"
    echo "  onlyoffice-uninstall --dry-run          # Show what would be removed"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Function to confirm action
confirm_action() {
    local message="$1"
    local force="$2"
    
    if [[ "$force" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi
}

# Function to check current installation
check_installation() {
    local dry_run="$1"
    
    echo -e "${BLUE}Checking current OnlyOffice installation...${NC}"
    
    # Check containers
    local containers
    containers=$(docker ps -a --format "{{.Names}}" | grep "^onlyoffice-" || true)
    local container_count=0
    if [[ -n "$containers" ]]; then
        container_count=$(echo "$containers" | wc -l)
    fi
    
    # Check volumes
    local volumes
    volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(onlyoffice|docspace)" || true)
    local volume_count=0
    if [[ -n "$volumes" ]]; then
        volume_count=$(echo "$volumes" | wc -l)
    fi
    
    # Check networks
    local networks
    networks=$(docker network ls --format "{{.Name}}" | grep "onlyoffice" || true)
    local network_count=0
    if [[ -n "$networks" ]]; then
        network_count=$(echo "$networks" | wc -l)
    fi
    
    # Check installation directory
    local install_dir_exists="false"
    if [[ -d "$ONLYOFFICE_DIR" ]]; then
        install_dir_exists="true"
    fi
    
    # Check data directory
    local data_exists="false"
    local data_size="0"
    if [[ -d "$ENCRYPTED_STORAGE" && "$(ls -A $ENCRYPTED_STORAGE 2>/dev/null)" ]]; then
        data_exists="true"
        data_size=$(du -sh "$ENCRYPTED_STORAGE" 2>/dev/null | cut -f1 || echo "unknown")
    fi
    
    echo ""
    echo -e "${BLUE}Current Installation Status:${NC}"
    echo "  Containers: $container_count"
    echo "  Docker Volumes: $volume_count"
    echo "  Docker Networks: $network_count"
    echo "  Installation Directory: $install_dir_exists"
    echo "  Data in Encrypted Storage: $data_exists ($data_size)"
    
    if [[ $container_count -eq 0 && $volume_count -eq 0 && $network_count -eq 0 && "$install_dir_exists" == "false" && "$data_exists" == "false" ]]; then
        echo -e "${GREEN}No OnlyOffice installation found${NC}"
        exit 0
    fi
    
    return 0
}

# Function to stop and remove containers
remove_containers() {
    local dry_run="$1"
    
    echo -e "${BLUE}Removing OnlyOffice containers...${NC}"
    
    local containers
    containers=$(docker ps -a --format "{{.Names}}" | grep "^onlyoffice-" || true)
    
    if [[ -z "$containers" ]]; then
        echo -e "  ${GREEN}✓${NC} No OnlyOffice containers found"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  Would stop and remove containers:"
        echo "$containers" | sed 's/^/    • /'
        return 0
    fi
    
    # Stop running containers
    local running_containers
    running_containers=$(docker ps --format "{{.Names}}" | grep "^onlyoffice-" || true)
    if [[ -n "$running_containers" ]]; then
        echo "  Stopping running containers..."
        docker stop $running_containers >/dev/null 2>&1 || true
        echo -e "  ${GREEN}✓${NC} Containers stopped"
    fi
    
    # Remove all containers
    echo "  Removing containers..."
    docker rm $containers >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} Containers removed"
}

# Function to remove Docker volumes
remove_volumes() {
    local dry_run="$1"
    
    echo -e "${BLUE}Removing OnlyOffice Docker volumes...${NC}"
    
    local volumes
    volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(onlyoffice|docspace)" || true)
    
    if [[ -z "$volumes" ]]; then
        echo -e "  ${GREEN}✓${NC} No OnlyOffice volumes found"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  Would remove volumes:"
        echo "$volumes" | sed 's/^/    • /'
        return 0
    fi
    
    echo "  Removing volumes..."
    docker volume rm $volumes >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} Volumes removed"
}

# Function to remove Docker networks
remove_networks() {
    local dry_run="$1"
    
    echo -e "${BLUE}Removing OnlyOffice Docker networks...${NC}"
    
    local networks
    networks=$(docker network ls --format "{{.Name}}" | grep "onlyoffice" || true)
    
    if [[ -z "$networks" ]]; then
        echo -e "  ${GREEN}✓${NC} No OnlyOffice networks found"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  Would remove networks:"
        echo "$networks" | sed 's/^/    • /'
        return 0
    fi
    
    echo "  Removing networks..."
    docker network rm $networks >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} Networks removed"
}

# Function to remove installation directory
remove_installation_dir() {
    local dry_run="$1"
    
    echo -e "${BLUE}Removing OnlyOffice installation directory...${NC}"
    
    if [[ ! -d "$ONLYOFFICE_DIR" ]]; then
        echo -e "  ${GREEN}✓${NC} Installation directory does not exist"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  Would remove directory: $ONLYOFFICE_DIR"
        local dir_size
        dir_size=$(du -sh "$ONLYOFFICE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  Directory size: $dir_size"
        return 0
    fi
    
    echo "  Removing $ONLYOFFICE_DIR..."
    rm -rf "$ONLYOFFICE_DIR"
    echo -e "  ${GREEN}✓${NC} Installation directory removed"
}

# Function to clean encrypted storage data
clean_encrypted_storage() {
    local dry_run="$1"
    local keep_data="$2"
    local keep_storage="$3"
    
    if [[ "$keep_data" == "true" ]]; then
        echo -e "${YELLOW}Keeping data in encrypted storage (--keep-data specified)${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Cleaning encrypted storage data...${NC}"
    
    if [[ ! -d "$ENCRYPTED_STORAGE" ]]; then
        echo -e "  ${GREEN}✓${NC} Encrypted storage directory does not exist"
        return 0
    fi
    
    # Check if directory has content
    if [[ -z "$(ls -A $ENCRYPTED_STORAGE 2>/dev/null)" ]]; then
        echo -e "  ${GREEN}✓${NC} Encrypted storage is already empty"
        return 0
    fi
    
    local data_size
    data_size=$(du -sh "$ENCRYPTED_STORAGE" 2>/dev/null | cut -f1 || echo "unknown")
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  Would remove data from: $ENCRYPTED_STORAGE"
        echo "  Data size: $data_size"
        echo "  Would preserve mount point directory"
        return 0
    fi
    
    if [[ "$keep_storage" == "true" ]]; then
        echo "  Keeping storage directory structure (--keep-storage specified)"
        echo "  Current data size: $data_size"
        return 0
    fi
    
    echo "  Removing data from encrypted storage ($data_size)..."
    echo "  Preserving mount point: $ENCRYPTED_STORAGE"
    
    # Remove contents but keep the mount point directory
    rm -rf ${ENCRYPTED_STORAGE}/* ${ENCRYPTED_STORAGE}/.* 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Encrypted storage data removed"
}

# Function to show final status
show_final_status() {
    echo ""
    echo -e "${BLUE}Uninstall Summary:${NC}"
    
    # Check remaining items
    local remaining_containers
    remaining_containers=$(docker ps -a --format "{{.Names}}" | grep "^onlyoffice-" | wc -l || echo "0")
    
    local remaining_volumes
    remaining_volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(onlyoffice|docspace)" | wc -l || echo "0")
    
    local remaining_networks
    remaining_networks=$(docker network ls --format "{{.Name}}" | grep "onlyoffice" | wc -l || echo "0")
    
    local install_dir_exists="No"
    if [[ -d "$ONLYOFFICE_DIR" ]]; then
        install_dir_exists="Yes"
    fi
    
    local data_exists="No"
    if [[ -d "$ENCRYPTED_STORAGE" && -n "$(ls -A $ENCRYPTED_STORAGE 2>/dev/null)" ]]; then
        data_exists="Yes"
    fi
    
    echo "  Containers remaining: $remaining_containers"
    echo "  Volumes remaining: $remaining_volumes"
    echo "  Networks remaining: $remaining_networks"
    echo "  Installation directory exists: $install_dir_exists"
    echo "  Data in encrypted storage: $data_exists"
    
    if [[ $remaining_containers -eq 0 && $remaining_volumes -eq 0 && $remaining_networks -eq 0 && "$install_dir_exists" == "No" ]]; then
        echo ""
        echo -e "${GREEN}✅ OnlyOffice DocSpace has been completely uninstalled${NC}"
        echo ""
        echo "Preserved:"
        echo "  • Encrypted storage mount point: $ENCRYPTED_STORAGE"
        echo "  • OnlyOffice deployment toolkit scripts"
        echo "  • Docker installation"
    else
        echo ""
        echo -e "${YELLOW}⚠ Uninstall completed with some items remaining${NC}"
    fi
}

# Main function
main() {
    local force="false" dry_run="false" keep_data="false" keep_storage="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --force)
                force="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --keep-data)
                keep_data="true"
                shift
                ;;
            --keep-storage)
                keep_storage="true"
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
    
    echo -e "${BLUE}OnlyOffice DocSpace Complete Uninstall${NC}"
    echo "$(date)"
    echo ""
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
        echo ""
    fi
    
    check_root
    check_installation "$dry_run"
    
    if [[ "$dry_run" != "true" ]]; then
        echo ""
        confirm_action "This will completely remove OnlyOffice DocSpace from your system." "$force"
        echo ""
    fi
    
    # Perform uninstall steps
    remove_containers "$dry_run"
    remove_volumes "$dry_run"  
    remove_networks "$dry_run"
    remove_installation_dir "$dry_run"
    clean_encrypted_storage "$dry_run" "$keep_data" "$keep_storage"
    
    if [[ "$dry_run" != "true" ]]; then
        show_final_status
    else
        echo ""
        echo -e "${BLUE}Dry run completed - no changes were made${NC}"
        echo "Run without --dry-run to perform actual uninstall"
    fi
}

# Run main function
main "$@"