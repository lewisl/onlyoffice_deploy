#!/bin/bash

# OnlyOffice Discovery Script
# This script installs OnlyOffice and captures all architecture details during the process

set -e

DISCOVERY_DIR="/root/onlyoffice-deployment-toolkit/discovery-data"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create discovery data directory
mkdir -p "$DISCOVERY_DIR"

echo "=== OnlyOffice Architecture Discovery Script ==="
echo "Discovery data will be saved to: $DISCOVERY_DIR"
echo "Timestamp: $TIMESTAMP"
echo ""

# Function to capture system state
capture_state() {
    local stage="$1"
    local stage_dir="$DISCOVERY_DIR/${stage}_${TIMESTAMP}"
    mkdir -p "$stage_dir"
    
    echo "Capturing system state: $stage"
    
    # Docker state
    echo "=== Docker Containers ===" > "$stage_dir/docker_containers.txt"
    docker ps -a >> "$stage_dir/docker_containers.txt" 2>&1 || echo "No containers" >> "$stage_dir/docker_containers.txt"
    
    echo "=== Docker Images ===" > "$stage_dir/docker_images.txt"
    docker images >> "$stage_dir/docker_images.txt" 2>&1 || echo "No images" >> "$stage_dir/docker_images.txt"
    
    echo "=== Docker Volumes ===" > "$stage_dir/docker_volumes.txt"
    docker volume ls >> "$stage_dir/docker_volumes.txt" 2>&1 || echo "No volumes" >> "$stage_dir/docker_volumes.txt"
    
    echo "=== Docker Networks ===" > "$stage_dir/docker_networks.txt"
    docker network ls >> "$stage_dir/docker_networks.txt" 2>&1 || echo "No networks" >> "$stage_dir/docker_networks.txt"
    
    # Detailed volume inspection
    echo "=== Volume Details ===" > "$stage_dir/volume_details.txt"
    for volume in $(docker volume ls -q 2>/dev/null || true); do
        echo "--- Volume: $volume ---" >> "$stage_dir/volume_details.txt"
        docker volume inspect "$volume" >> "$stage_dir/volume_details.txt" 2>&1 || true
        echo "" >> "$stage_dir/volume_details.txt"
    done
    
    # Network inspection
    echo "=== Network Details ===" > "$stage_dir/network_details.txt"
    for network in $(docker network ls -q 2>/dev/null || true); do
        echo "--- Network: $network ---" >> "$stage_dir/network_details.txt"
        docker network inspect "$network" >> "$stage_dir/network_details.txt" 2>&1 || true
        echo "" >> "$stage_dir/network_details.txt"
    done
    
    # System processes
    echo "=== System Processes ===" > "$stage_dir/processes.txt"
    ps aux >> "$stage_dir/processes.txt" 2>&1 || true
    
    # System services
    echo "=== Systemd Services ===" > "$stage_dir/systemd_services.txt"
    systemctl list-units --all | grep -i onlyoffice >> "$stage_dir/systemd_services.txt" 2>&1 || echo "No OnlyOffice services" >> "$stage_dir/systemd_services.txt"
    systemctl list-units --all | grep -i docspace >> "$stage_dir/systemd_services.txt" 2>&1 || echo "No DocSpace services" >> "$stage_dir/systemd_services.txt"
    
    # File system state
    echo "=== OnlyOffice Directories ===" > "$stage_dir/filesystem.txt"
    find /root /opt /var /etc -name "*onlyoffice*" -o -name "*docspace*" 2>/dev/null >> "$stage_dir/filesystem.txt" || echo "No OnlyOffice directories found" >> "$stage_dir/filesystem.txt"
    
    # Port usage
    echo "=== Network Ports ===" > "$stage_dir/ports.txt"
    netstat -tulpn >> "$stage_dir/ports.txt" 2>&1 || ss -tulpn >> "$stage_dir/ports.txt" 2>&1 || echo "Could not capture port information" >> "$stage_dir/ports.txt"
    
    echo "State captured for stage: $stage"
    echo ""
}

# Function to capture docker-compose files
capture_compose_files() {
    local stage="$1"
    local stage_dir="$DISCOVERY_DIR/${stage}_${TIMESTAMP}"
    
    echo "=== Docker Compose Files ===" > "$stage_dir/compose_files.txt"
    find /root /opt /var -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null >> "$stage_dir/compose_files.txt" || echo "No compose files found" >> "$stage_dir/compose_files.txt"
    
    # Copy actual compose files
    mkdir -p "$stage_dir/compose_configs"
    while IFS= read -r compose_file; do
        if [[ -f "$compose_file" ]]; then
            cp "$compose_file" "$stage_dir/compose_configs/" 2>/dev/null || true
        fi
    done < <(find /root /opt /var -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null || true)
}

# Function to capture container details
capture_container_details() {
    local stage="$1"
    local stage_dir="$DISCOVERY_DIR/${stage}_${TIMESTAMP}"
    mkdir -p "$stage_dir/container_details"
    
    for container in $(docker ps -aq 2>/dev/null || true); do
        container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^.//' || echo "unknown")
        echo "Capturing details for container: $container_name"
        
        # Container inspection
        docker inspect "$container" > "$stage_dir/container_details/${container_name}_inspect.json" 2>/dev/null || true
        
        # Container logs (last 100 lines)
        docker logs --tail=100 "$container" > "$stage_dir/container_details/${container_name}_logs.txt" 2>&1 || echo "Could not capture logs" > "$stage_dir/container_details/${container_name}_logs.txt"
        
        # Container processes
        docker top "$container" > "$stage_dir/container_details/${container_name}_processes.txt" 2>/dev/null || echo "Container not running" > "$stage_dir/container_details/${container_name}_processes.txt"
    done
}

echo "=== STAGE 1: Pre-Installation State ==="
capture_state "pre_install"

echo "=== STAGE 2: Installing OnlyOffice DocSpace ==="
echo "Downloading OnlyOffice installation script..."

# Download the official installation script
curl -fsSL https://download.onlyoffice.com/docspace/docspace-install.sh -o /tmp/docspace-install.sh
chmod +x /tmp/docspace-install.sh

echo "Installation script downloaded. Beginning installation..."
echo "This will install OnlyOffice DocSpace with default settings."
echo ""

# Capture the installation process
echo "=== Installation Log ===" > "$DISCOVERY_DIR/installation_log_${TIMESTAMP}.txt"

# Run the installation script with output capture
if /tmp/docspace-install.sh --makeswap false 2>&1 | tee -a "$DISCOVERY_DIR/installation_log_${TIMESTAMP}.txt"; then
    echo "Installation completed successfully"
else
    echo "Installation encountered issues - continuing with discovery"
fi

echo ""
echo "=== STAGE 3: Post-Installation State ==="
capture_state "post_install"
capture_compose_files "post_install"
capture_container_details "post_install"

echo "=== STAGE 4: Container Dependency Analysis ==="
# Wait for containers to stabilize
echo "Waiting 30 seconds for containers to stabilize..."
sleep 30

# Capture final state
capture_state "final_state"
capture_container_details "final_state"

echo "=== STAGE 5: Architecture Analysis ==="
analysis_file="$DISCOVERY_DIR/architecture_analysis_${TIMESTAMP}.txt"

echo "=== OnlyOffice Architecture Analysis ===" > "$analysis_file"
echo "Generated: $(date)" >> "$analysis_file"
echo "" >> "$analysis_file"

echo "=== Container Count and Overview ===" >> "$analysis_file"
container_count=$(docker ps -a | wc -l)
running_count=$(docker ps | wc -l)
echo "Total containers: $((container_count - 1))" >> "$analysis_file"
echo "Running containers: $((running_count - 1))" >> "$analysis_file"
echo "" >> "$analysis_file"

echo "=== Container List with Status ===" >> "$analysis_file"
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" >> "$analysis_file" 2>&1 || true
echo "" >> "$analysis_file"

echo "=== Volume Mappings ===" >> "$analysis_file"
for container in $(docker ps -aq 2>/dev/null || true); do
    container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^.//' || echo "unknown")
    echo "--- $container_name ---" >> "$analysis_file"
    docker inspect --format='{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}' "$container" >> "$analysis_file" 2>/dev/null || true
    echo "" >> "$analysis_file"
done

echo "=== Network Configuration ===" >> "$analysis_file"
for container in $(docker ps -aq 2>/dev/null || true); do
    container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^.//' || echo "unknown")
    echo "--- $container_name ---" >> "$analysis_file"
    docker inspect --format='{{range $net, $conf := .NetworkSettings.Networks}}Network: {{$net}}, IP: {{$conf.IPAddress}}{{"\n"}}{{end}}' "$container" >> "$analysis_file" 2>/dev/null || true
    echo "" >> "$analysis_file"
done

echo ""
echo "=== DISCOVERY COMPLETE ==="
echo "All data has been captured in: $DISCOVERY_DIR"
echo "Key files created:"
echo "- Installation log: $DISCOVERY_DIR/installation_log_${TIMESTAMP}.txt"
echo "- Architecture analysis: $analysis_file"
echo "- Pre/post installation states in timestamped directories"
echo "- Container details and configurations"
echo ""
echo "OnlyOffice should now be accessible at: http://$(hostname -I | awk '{print $1}')"
echo ""
echo "Use the following commands to examine the installation:"
echo "  docker ps                    # View running containers"
echo "  docker images               # View installed images"
echo "  docker volume ls            # View created volumes"
echo "  docker network ls           # View networks"
echo ""
echo "Discovery script completed successfully!"