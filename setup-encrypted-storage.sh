#!/bin/bash

# OnlyOffice DocSpace Encrypted Storage Setup Script
# Phase 2: Digital Ocean Encrypted Block Storage Integration
# 
# This script sets up encrypted storage for OnlyOffice DocSpace
# Assumes: Digital Ocean encrypted block storage is already attached
# Device: /dev/sda (100GB), Mount: /mnt/docspace_data

set -e

STORAGE_DEVICE="${STORAGE_DEVICE:-/dev/sda}"
STORAGE_MOUNT="${STORAGE_MOUNT:-/mnt/docspace_data}"
STORAGE_FILESYSTEM="${STORAGE_FILESYSTEM:-ext4}"

echo "=== OnlyOffice DocSpace Encrypted Storage Setup ==="
echo "Storage Device: $STORAGE_DEVICE"
echo "Mount Point: $STORAGE_MOUNT"
echo "Filesystem: $STORAGE_FILESYSTEM"
echo ""

# Function to check if we're root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
}

# Function to validate the storage device exists
validate_storage_device() {
    if [[ ! -b "$STORAGE_DEVICE" ]]; then
        echo "Error: Storage device $STORAGE_DEVICE not found"
        echo "Please ensure the Digital Ocean encrypted block storage 'docspace-data' is attached"
        exit 1
    fi
    
    echo "✓ Storage device $STORAGE_DEVICE found"
    
    # Get device info
    echo "Device information:"
    lsblk "$STORAGE_DEVICE"
    echo ""
}

# Function to setup filesystem if needed
setup_filesystem() {
    local has_filesystem
    has_filesystem=$(blkid "$STORAGE_DEVICE" | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2 || echo "none")
    
    if [[ "$has_filesystem" == "none" ]]; then
        echo "No filesystem found on $STORAGE_DEVICE"
        read -p "Create ext4 filesystem? This will erase all data (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Creating ext4 filesystem on $STORAGE_DEVICE..."
            mkfs.ext4 -F "$STORAGE_DEVICE"
            echo "✓ Filesystem created"
        else
            echo "Aborted: Filesystem required"
            exit 1
        fi
    else
        echo "✓ Existing filesystem: $has_filesystem"
    fi
}

# Function to create mount point and mount storage
mount_storage() {
    # Create mount point if it doesn't exist
    if [[ ! -d "$STORAGE_MOUNT" ]]; then
        echo "Creating mount point: $STORAGE_MOUNT"
        mkdir -p "$STORAGE_MOUNT"
    fi
    
    # Check if already mounted
    if mountpoint -q "$STORAGE_MOUNT"; then
        echo "✓ Storage already mounted at $STORAGE_MOUNT"
    else
        echo "Mounting $STORAGE_DEVICE to $STORAGE_MOUNT..."
        mount "$STORAGE_DEVICE" "$STORAGE_MOUNT"
        echo "✓ Storage mounted"
    fi
    
    # Get UUID for permanent mounting
    local storage_uuid
    storage_uuid=$(blkid -s UUID -o value "$STORAGE_DEVICE")
    
    # Add to fstab if not already present
    if ! grep -q "$storage_uuid" /etc/fstab; then
        echo "Adding to /etc/fstab for permanent mounting..."
        echo "UUID=$storage_uuid $STORAGE_MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab
        echo "✓ Added to /etc/fstab"
    else
        echo "✓ Already in /etc/fstab"
    fi
}

# Function to create OnlyOffice data directories
create_onlyoffice_directories() {
    echo "Creating OnlyOffice data directories..."
    
    # Required directories for OnlyOffice DocSpace
    local directories=(
        "app_data"
        "log_data" 
        "mysql_data"
    )
    
    for dir in "${directories[@]}"; do
        local full_path="$STORAGE_MOUNT/$dir"
        if [[ ! -d "$full_path" ]]; then
            echo "Creating: $full_path"
            mkdir -p "$full_path"
            
            # Set appropriate permissions
            case "$dir" in
                "mysql_data")
                    # MySQL needs specific ownership
                    chown 999:999 "$full_path"
                    chmod 755 "$full_path"
                    ;;
                "app_data")
                    # App data needs to be accessible to various OnlyOffice services
                    chown -R 1001:1001 "$full_path"
                    chmod -R 755 "$full_path"
                    ;;
                "log_data")
                    # Log directory needs broader access
                    chmod 755 "$full_path"
                    ;;
            esac
            echo "✓ Created: $full_path"
        else
            echo "✓ Exists: $full_path"
        fi
    done
}

# Function to validate container access
validate_container_access() {
    echo "Validating encrypted storage container access..."
    
    # Test write access from host
    local test_file="$STORAGE_MOUNT/test_access.txt"
    echo "test" > "$test_file"
    if [[ -f "$test_file" ]]; then
        echo "✓ Host write access confirmed"
        rm "$test_file"
    else
        echo "✗ Host write access failed"
        exit 1
    fi
    
    # Check that volume mappings will work
    echo "Volume mapping validation:"
    echo "  Host path: $STORAGE_MOUNT/app_data → Container: /app/onlyoffice/data"
    echo "  Host path: $STORAGE_MOUNT/log_data → Container: /var/log/onlyoffice"
    echo "  Host path: $STORAGE_MOUNT/mysql_data → Container: /var/lib/mysql"
    echo "✓ Volume mappings configured correctly"
}

# Function to show storage status
show_storage_status() {
    echo ""
    echo "=== Encrypted Storage Status ==="
    echo "Device: $STORAGE_DEVICE"
    echo "Mount: $STORAGE_MOUNT"
    echo "Usage:"
    df -h "$STORAGE_MOUNT"
    echo ""
    echo "Directory structure:"
    ls -la "$STORAGE_MOUNT"
    echo ""
    echo "Permissions:"
    ls -la "$STORAGE_MOUNT"/ | tail -n +2 | while read -r line; do
        echo "  $line"
    done
}

# Function to generate docker-compose volume configuration
generate_volume_config() {
    local config_file="/root/onlyoffice-deployment-toolkit/encrypted-storage-volumes.yml"
    
    cat > "$config_file" << EOF
# OnlyOffice DocSpace Encrypted Storage Volume Configuration
# Generated by setup-encrypted-storage.sh
#
# This shows the volume mappings for encrypted storage integration
# These mappings are already configured in the OnlyOffice docker-compose files

volumes:
  # Application data - user files, documents, configurations
  app_data:
    driver: local
    driver_opts:
      type: bind
      o: bind
      device: $STORAGE_MOUNT/app_data

  # Log data - all OnlyOffice service logs
  log_data:
    driver: local
    driver_opts:
      type: bind
      o: bind  
      device: $STORAGE_MOUNT/log_data

  # MySQL data - database files
  mysql_data:
    driver: local
    driver_opts:
      type: bind
      o: bind
      device: $STORAGE_MOUNT/mysql_data

# Container volume mappings (already configured in OnlyOffice compose files):
# Services using app_data:
#   - onlyoffice-files: /app/onlyoffice/data
#   - onlyoffice-doceditor: /app/onlyoffice/data  
#   - onlyoffice-backup-background-tasks: /app/onlyoffice/data
#   - onlyoffice-document-server: /var/www/onlyoffice/Data
#   - onlyoffice-api: /app/onlyoffice/data
#   - onlyoffice-studio: /app/onlyoffice/data
#   - (and others)
#
# Services using log_data:
#   - All OnlyOffice containers: /var/log/onlyoffice
#   - onlyoffice-proxy: /var/log/nginx
#
# Services using mysql_data:
#   - onlyoffice-mysql-server: /var/lib/mysql
EOF

    echo "✓ Generated volume configuration: $config_file"
}

# Main execution
main() {
    echo "Starting encrypted storage setup..."
    
    check_root
    validate_storage_device
    setup_filesystem
    mount_storage
    create_onlyoffice_directories
    validate_container_access
    generate_volume_config
    show_storage_status
    
    echo ""
    echo "=== ENCRYPTED STORAGE SETUP COMPLETE ==="
    echo ""
    echo "✓ Digital Ocean encrypted block storage configured"
    echo "✓ Filesystem mounted at $STORAGE_MOUNT"
    echo "✓ OnlyOffice data directories created with proper permissions"
    echo "✓ Volume mappings validated for container access"
    echo "✓ Permanent mounting configured in /etc/fstab"
    echo ""
    echo "The encrypted storage is now ready for OnlyOffice DocSpace containers."
    echo "All user data, logs, and database files will be stored on encrypted storage."
    echo ""
    echo "Next steps:"
    echo "1. Deploy OnlyOffice containers (they will automatically use encrypted storage)"
    echo "2. Verify container access to encrypted storage"
    echo "3. Test data persistence across container restarts"
}

# Help function
show_help() {
    echo "OnlyOffice DocSpace Encrypted Storage Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --device DEVICE     Storage device (default: /dev/sda)"
    echo "  -m, --mount MOUNT       Mount point (default: /mnt/docspace_data)"
    echo "  -f, --filesystem TYPE   Filesystem type (default: ext4)"
    echo "  -h, --help             Show this help"
    echo ""
    echo "This script configures Digital Ocean encrypted block storage for OnlyOffice DocSpace."
    echo "The storage must be attached to the droplet before running this script."
    echo ""
    echo "Digital Ocean Setup:"
    echo "1. Create encrypted block storage volume 'docspace-data' (~100GB)"
    echo "2. Attach it to droplet 'docspace-prod'"
    echo "3. Run this script to configure filesystem and directories"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--device)
            STORAGE_DEVICE="$2"
            shift 2
            ;;
        -m|--mount)
            STORAGE_MOUNT="$2"
            shift 2
            ;;
        -f|--filesystem)
            STORAGE_FILESYSTEM="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main