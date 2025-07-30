#!/bin/bash

# OnlyOffice Discovery Script v2 - Bounded and Limited
# This script installs OnlyOffice and captures architecture details with strict output limits

set -e

DISCOVERY_DIR="/root/onlyoffice-deployment-toolkit/discovery-data"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Output limits
MAX_LINES=1000
MAX_LOG_LINES=50
TIMEOUT_SECONDS=300
MAX_FIND_RESULTS=100

# Create discovery data directory
mkdir -p "$DISCOVERY_DIR"

echo "=== OnlyOffice Architecture Discovery Script v2 ==="
echo "Discovery data will be saved to: $DISCOVERY_DIR"
echo "Timestamp: $TIMESTAMP"
echo "Output limits: $MAX_LINES lines per file, $MAX_LOG_LINES log lines, ${TIMEOUT_SECONDS}s timeout"
echo ""

# Function to limit output lines
limit_output() {
    head -n "$MAX_LINES"
}

# Function to limit find results
limit_find() {
    head -n "$MAX_FIND_RESULTS"
}

# Function to capture system state with limits
capture_state() {
    local stage="$1"
    local stage_dir="$DISCOVERY_DIR/${stage}_${TIMESTAMP}"
    mkdir -p "$stage_dir"
    
    echo "Capturing system state: $stage (limited output)"
    
    # Docker state with limits
    echo "=== Docker Containers ===" > "$stage_dir/docker_containers.txt"
    timeout 30 docker ps -a 2>&1 | limit_output >> "$stage_dir/docker_containers.txt" || echo "Timeout or error capturing containers" >> "$stage_dir/docker_containers.txt"
    
    echo "=== Docker Images ===" > "$stage_dir/docker_images.txt"
    timeout 30 docker images 2>&1 | limit_output >> "$stage_dir/docker_images.txt" || echo "Timeout or error capturing images" >> "$stage_dir/docker_images.txt"
    
    echo "=== Docker Volumes ===" > "$stage_dir/docker_volumes.txt"
    timeout 30 docker volume ls 2>&1 | limit_output >> "$stage_dir/docker_volumes.txt" || echo "Timeout or error capturing volumes" >> "$stage_dir/docker_volumes.txt"
    
    echo "=== Docker Networks ===" > "$stage_dir/docker_networks.txt"
    timeout 30 docker network ls 2>&1 | limit_output >> "$stage_dir/docker_networks.txt" || echo "Timeout or error capturing networks" >> "$stage_dir/docker_networks.txt"
    
    # Limited volume inspection (max 10 volumes)
    echo "=== Volume Details (Limited) ===" > "$stage_dir/volume_details.txt"
    volume_count=0
    for volume in $(docker volume ls -q 2>/dev/null | head -10 || true); do
        if [[ $volume_count -ge 10 ]]; then
            echo "... (limiting to first 10 volumes)" >> "$stage_dir/volume_details.txt"
            break
        fi
        echo "--- Volume: $volume ---" >> "$stage_dir/volume_details.txt"
        timeout 15 docker volume inspect "$volume" 2>&1 | limit_output >> "$stage_dir/volume_details.txt" || echo "Timeout inspecting volume" >> "$stage_dir/volume_details.txt"
        echo "" >> "$stage_dir/volume_details.txt"
        ((volume_count++))
    done
    
    # Limited network inspection (max 10 networks)  
    echo "=== Network Details (Limited) ===" > "$stage_dir/network_details.txt"
    network_count=0
    for network in $(docker network ls -q 2>/dev/null | head -10 || true); do
        if [[ $network_count -ge 10 ]]; then
            echo "... (limiting to first 10 networks)" >> "$stage_dir/network_details.txt"
            break
        fi
        echo "--- Network: $network ---" >> "$stage_dir/network_details.txt"
        timeout 15 docker network inspect "$network" 2>&1 | limit_output >> "$stage_dir/network_details.txt" || echo "Timeout inspecting network" >> "$stage_dir/network_details.txt"
        echo "" >> "$stage_dir/network_details.txt"
        ((network_count++))
    done
    
    # System processes (limited)
    echo "=== System Processes (Limited) ===" > "$stage_dir/processes.txt"
    timeout 30 ps aux 2>&1 | limit_output >> "$stage_dir/processes.txt" || echo "Timeout capturing processes" >> "$stage_dir/processes.txt"
    
    # System services (targeted search)
    echo "=== OnlyOffice/DocSpace Services ===" > "$stage_dir/systemd_services.txt"
    timeout 30 systemctl list-units --all 2>&1 | grep -i -E "(onlyoffice|docspace)" | limit_output >> "$stage_dir/systemd_services.txt" || echo "No OnlyOffice/DocSpace services found" >> "$stage_dir/systemd_services.txt"
    
    # File system state (limited and targeted)
    echo "=== OnlyOffice Directories (Limited) ===" > "$stage_dir/filesystem.txt"
    timeout 60 find /root /opt /var /etc -maxdepth 3 -name "*onlyoffice*" -o -name "*docspace*" 2>/dev/null | limit_find >> "$stage_dir/filesystem.txt" || echo "Timeout or no OnlyOffice directories found" >> "$stage_dir/filesystem.txt"
    
    # Port usage (limited)
    echo "=== Network Ports (Limited) ===" > "$stage_dir/ports.txt"
    timeout 30 netstat -tulpn 2>&1 | limit_output >> "$stage_dir/ports.txt" || timeout 30 ss -tulpn 2>&1 | limit_output >> "$stage_dir/ports.txt" || echo "Could not capture port information" >> "$stage_dir/ports.txt"
    
    echo "State captured for stage: $stage"
    echo ""
}

# Function to capture docker-compose files with limits
capture_compose_files() {
    local stage="$1"
    local stage_dir="$DISCOVERY_DIR/${stage}_${TIMESTAMP}"
    
    echo "=== Docker Compose Files (Limited) ===" > "$stage_dir/compose_files.txt"
    timeout 60 find /root /opt /var -maxdepth 4 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null | limit_find >> "$stage_dir/compose_files.txt" || echo "Timeout or no compose files found" >> "$stage_dir/compose_files.txt"
    
    # Copy actual compose files (limit to first 10)
    mkdir -p "$stage_dir/compose_configs"
    file_count=0
    while IFS= read -r compose_file && [[ $file_count -lt 10 ]]; do
        if [[ -f "$compose_file" && -s "$compose_file" ]]; then
            # Check file size before copying (skip if > 1MB)
            file_size=$(stat -f%z "$compose_file" 2>/dev/null || stat -c%s "$compose_file" 2>/dev/null || echo "0")
            if [[ $file_size -lt 1048576 ]]; then
                cp "$compose_file" "$stage_dir/compose_configs/" 2>/dev/null || true
                ((file_count++))
            else
                echo "Skipped large file: $compose_file (${file_size} bytes)" >> "$stage_dir/compose_files.txt"
            fi
        fi
    done < <(timeout 60 find /root /opt /var -maxdepth 4 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null || true)
}

# Function to capture container details with strict limits
capture_container_details() {
    local stage="$1"
    local stage_dir="$DISCOVERY_DIR/${stage}_${TIMESTAMP}"
    mkdir -p "$stage_dir/container_details"
    
    container_count=0
    for container in $(docker ps -aq 2>/dev/null | head -20 || true); do
        if [[ $container_count -ge 20 ]]; then
            echo "... (limiting to first 20 containers)" > "$stage_dir/container_details/limit_notice.txt"
            break
        fi
        
        container_name=$(timeout 10 docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^.//' || echo "unknown_${container_count}")
        echo "Capturing details for container: $container_name"
        
        # Container inspection (with size limit check)
        timeout 30 docker inspect "$container" 2>/dev/null | head -c 102400 > "$stage_dir/container_details/${container_name}_inspect.json" || echo '{"error": "timeout or large output"}' > "$stage_dir/container_details/${container_name}_inspect.json"
        
        # Container logs (strict limits)
        timeout 15 docker logs --tail=$MAX_LOG_LINES "$container" 2>&1 | head -c 51200 > "$stage_dir/container_details/${container_name}_logs.txt" || echo "Could not capture logs or timeout" > "$stage_dir/container_details/${container_name}_logs.txt"
        
        # Container processes
        timeout 10 docker top "$container" 2>/dev/null | limit_output > "$stage_dir/container_details/${container_name}_processes.txt" || echo "Container not running or timeout" > "$stage_dir/container_details/${container_name}_processes.txt"
        
        ((container_count++))
    done
}

echo "=== STAGE 1: Pre-Installation State ==="
capture_state "pre_install"

echo "=== STAGE 2: Installing OnlyOffice DocSpace ==="
echo "Downloading OnlyOffice installation script..."

# Download the official installation script with timeout
if ! timeout 120 curl -fsSL https://download.onlyoffice.com/docspace/docspace-install.sh -o /tmp/docspace-install.sh; then
    echo "ERROR: Failed to download installation script (timeout or network error)"
    exit 1
fi

chmod +x /tmp/docspace-install.sh

echo "Installation script downloaded. Beginning installation with output limits..."
echo ""

# Capture the installation process with strict limits
installation_log="$DISCOVERY_DIR/installation_log_${TIMESTAMP}.txt"
echo "=== Installation Log (Limited) ===" > "$installation_log"
echo "Started: $(date)" >> "$installation_log"

# Run the installation script with output capture and limits
echo "Running installation with ${TIMEOUT_SECONDS}s timeout and output limits..."
if timeout $TIMEOUT_SECONDS /tmp/docspace-install.sh --makeswap false 2>&1 | head -c 1048576 | tee -a "$installation_log"; then
    echo "Installation completed within timeout" >> "$installation_log"
    echo "Installation completed successfully"
else
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "Installation timed out after ${TIMEOUT_SECONDS} seconds" >> "$installation_log"
        echo "WARNING: Installation timed out - continuing with discovery"
    else
        echo "Installation exited with code $exit_code" >> "$installation_log"
        echo "WARNING: Installation encountered issues - continuing with discovery"
    fi
fi

echo "Completed: $(date)" >> "$installation_log"

echo ""
echo "=== STAGE 3: Post-Installation State ==="
capture_state "post_install"
capture_compose_files "post_install"
capture_container_details "post_install"

echo "=== STAGE 4: Container Dependency Analysis ==="
# Wait for containers to stabilize (reduced time)
echo "Waiting 15 seconds for containers to stabilize..."
sleep 15

# Capture final state
capture_state "final_state"
capture_container_details "final_state"

echo "=== STAGE 5: Architecture Analysis ==="
analysis_file="$DISCOVERY_DIR/architecture_analysis_${TIMESTAMP}.txt"

echo "=== OnlyOffice Architecture Analysis ===" > "$analysis_file"
echo "Generated: $(date)" >> "$analysis_file"
echo "Output limited to prevent runaway logging" >> "$analysis_file"
echo "" >> "$analysis_file"

echo "=== Container Count and Overview ===" >> "$analysis_file"
container_count=$(timeout 10 docker ps -a 2>/dev/null | wc -l || echo "1")
running_count=$(timeout 10 docker ps 2>/dev/null | wc -l || echo "1")
echo "Total containers: $((container_count - 1))" >> "$analysis_file"
echo "Running containers: $((running_count - 1))" >> "$analysis_file"
echo "" >> "$analysis_file"

echo "=== Container List with Status (Limited) ===" >> "$analysis_file"
timeout 30 docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>&1 | limit_output >> "$analysis_file" || echo "Timeout capturing container list" >> "$analysis_file"
echo "" >> "$analysis_file"

echo "=== Volume Mappings (Limited) ===" >> "$analysis_file"
container_count=0
for container in $(docker ps -aq 2>/dev/null | head -10 || true); do
    if [[ $container_count -ge 10 ]]; then
        echo "... (limiting to first 10 containers)" >> "$analysis_file"
        break
    fi
    container_name=$(timeout 5 docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^.//' || echo "unknown_${container_count}")
    echo "--- $container_name ---" >> "$analysis_file"
    timeout 10 docker inspect --format='{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}' "$container" 2>/dev/null | limit_output >> "$analysis_file" || echo "Timeout inspecting mounts" >> "$analysis_file"
    echo "" >> "$analysis_file"
    ((container_count++))
done

echo "=== Network Configuration (Limited) ===" >> "$analysis_file"
container_count=0
for container in $(docker ps -aq 2>/dev/null | head -10 || true); do
    if [[ $container_count -ge 10 ]]; then
        echo "... (limiting to first 10 containers)" >> "$analysis_file"
        break
    fi
    container_name=$(timeout 5 docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^.//' || echo "unknown_${container_count}")
    echo "--- $container_name ---" >> "$analysis_file"
    timeout 10 docker inspect --format='{{range $net, $conf := .NetworkSettings.Networks}}Network: {{$net}}, IP: {{$conf.IPAddress}}{{"\n"}}{{end}}' "$container" 2>/dev/null | limit_output >> "$analysis_file" || echo "Timeout inspecting networks" >> "$analysis_file"
    echo "" >> "$analysis_file"
    ((container_count++))
done

echo ""
echo "=== DISCOVERY COMPLETE ==="
echo "All data has been captured with output limits in: $DISCOVERY_DIR"
echo "Key files created:"
echo "- Installation log: $installation_log"
echo "- Architecture analysis: $analysis_file"
echo "- Pre/post installation states in timestamped directories"
echo "- Container details and configurations (limited)"
echo ""
echo "Output limits applied:"
echo "- Max lines per file: $MAX_LINES"
echo "- Max log lines per container: $MAX_LOG_LINES" 
echo "- Max containers analyzed: 20"
echo "- Max volumes/networks analyzed: 10"
echo "- Installation timeout: ${TIMEOUT_SECONDS}s"
echo ""

# Try to get the IP address
host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo "OnlyOffice may be accessible at: http://$host_ip"
echo ""
echo "Use the following commands to examine the installation:"
echo "  docker ps                    # View running containers"
echo "  docker images               # View installed images"  
echo "  docker volume ls            # View created volumes"
echo "  docker network ls           # View networks"
echo ""
echo "Discovery script v2 completed successfully with output limits!"