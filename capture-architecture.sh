#!/bin/bash

# OnlyOffice Architecture Capture Script
# Captures the architecture of an already-running OnlyOffice installation

DISCOVERY_DIR="/root/onlyoffice-deployment-toolkit/architecture-capture"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "$DISCOVERY_DIR"

echo "=== OnlyOffice Architecture Capture ==="
echo "Timestamp: $TIMESTAMP"
echo "Capturing data to: $DISCOVERY_DIR"
echo ""

# Capture container information
echo "=== Container Overview ===" > "$DISCOVERY_DIR/containers.txt"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" >> "$DISCOVERY_DIR/containers.txt"
echo "" >> "$DISCOVERY_DIR/containers.txt"
echo "Total containers: $(docker ps -q | wc -l)" >> "$DISCOVERY_DIR/containers.txt"

# Capture detailed container information
mkdir -p "$DISCOVERY_DIR/container-details"
for container in $(docker ps --format "{{.Names}}" | head -25); do
    echo "Capturing details for: $container"
    
    # Container inspection (limited)
    docker inspect "$container" | head -c 102400 > "$DISCOVERY_DIR/container-details/${container}_inspect.json" 2>/dev/null || echo "Failed to inspect" > "$DISCOVERY_DIR/container-details/${container}_inspect.json"
    
    # Container logs (last 50 lines)
    docker logs --tail=50 "$container" 2>&1 | head -c 51200 > "$DISCOVERY_DIR/container-details/${container}_logs.txt" || echo "No logs available" > "$DISCOVERY_DIR/container-details/${container}_logs.txt"
    
    # Container processes
    docker top "$container" 2>/dev/null > "$DISCOVERY_DIR/container-details/${container}_processes.txt" || echo "Container not running" > "$DISCOVERY_DIR/container-details/${container}_processes.txt"
done

# Capture Docker Compose configurations
echo "=== Docker Compose Files ===" > "$DISCOVERY_DIR/compose-configs.txt"
ls -la /app/onlyoffice/*.yml >> "$DISCOVERY_DIR/compose-configs.txt" 2>&1 || echo "No compose files found" >> "$DISCOVERY_DIR/compose-configs.txt"

mkdir -p "$DISCOVERY_DIR/compose-files"
cp /app/onlyoffice/*.yml "$DISCOVERY_DIR/compose-files/" 2>/dev/null || echo "Could not copy compose files"

# Capture volume mappings
echo "=== Volume Mappings ===" > "$DISCOVERY_DIR/volumes.txt"
for container in $(docker ps --format "{{.Names}}" | head -25); do
    echo "--- $container ---" >> "$DISCOVERY_DIR/volumes.txt"
    docker inspect --format='{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{"\n"}}{{end}}' "$container" >> "$DISCOVERY_DIR/volumes.txt" 2>/dev/null || echo "Could not inspect mounts" >> "$DISCOVERY_DIR/volumes.txt"
    echo "" >> "$DISCOVERY_DIR/volumes.txt"
done

# Capture network configuration
echo "=== Network Configuration ===" > "$DISCOVERY_DIR/networks.txt"
docker network ls >> "$DISCOVERY_DIR/networks.txt"
echo "" >> "$DISCOVERY_DIR/networks.txt"
for container in $(docker ps --format "{{.Names}}" | head -25); do
    echo "--- $container ---" >> "$DISCOVERY_DIR/networks.txt"
    docker inspect --format='{{range $net, $conf := .NetworkSettings.Networks}}Network: {{$net}}, IP: {{$conf.IPAddress}}{{"\n"}}{{end}}' "$container" >> "$DISCOVERY_DIR/networks.txt" 2>/dev/null || echo "Could not inspect networks" >> "$DISCOVERY_DIR/networks.txt"
    echo "" >> "$DISCOVERY_DIR/networks.txt"
done

# Capture environment variables (sanitized)
echo "=== Environment Variables (Sanitized) ===" > "$DISCOVERY_DIR/environment.txt"
cat /app/onlyoffice/.env | grep -v -i "password\|secret\|key\|token" >> "$DISCOVERY_DIR/environment.txt" 2>/dev/null || echo "No .env file found" >> "$DISCOVERY_DIR/environment.txt"

# Capture system ports
echo "=== Network Ports ===" > "$DISCOVERY_DIR/ports.txt"
netstat -tulpn | grep -E "(docker|onlyoffice)" | head -50 >> "$DISCOVERY_DIR/ports.txt" 2>/dev/null || ss -tulpn | grep -E "(docker|onlyoffice)" | head -50 >> "$DISCOVERY_DIR/ports.txt" 2>/dev/null || echo "Could not capture port information" >> "$DISCOVERY_DIR/ports.txt"

# Generate architecture summary
echo "=== OnlyOffice DocSpace Architecture Summary ===" > "$DISCOVERY_DIR/architecture-summary.txt"
echo "Generated: $(date)" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "" >> "$DISCOVERY_DIR/architecture-summary.txt"

echo "=== Container Architecture ===" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "Total containers: $(docker ps -q | wc -l)" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "OnlyOffice version: $(docker ps --format "{{.Image}}" | grep docspace | head -1 | cut -d: -f2)" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "" >> "$DISCOVERY_DIR/architecture-summary.txt"

echo "=== Service Categories ===" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "API Services:" >> "$DISCOVERY_DIR/architecture-summary.txt"
docker ps --format "{{.Names}}" | grep -E "(api|sdk)" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "" >> "$DISCOVERY_DIR/architecture-summary.txt"

echo "Frontend Services:" >> "$DISCOVERY_DIR/architecture-summary.txt"
docker ps --format "{{.Names}}" | grep -E "(studio|login|files|doceditor|socket)" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "" >> "$DISCOVERY_DIR/architecture-summary.txt"

echo "Backend Services:" >> "$DISCOVERY_DIR/architecture-summary.txt"
docker ps --format "{{.Names}}" | grep -E "(people|notify|backup|clear|ssoauth)" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "" >> "$DISCOVERY_DIR/architecture-summary.txt"

echo "Infrastructure Services:" >> "$DISCOVERY_DIR/architecture-summary.txt"
docker ps --format "{{.Names}}" | grep -E "(mysql|proxy|router|document-server)" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "" >> "$DISCOVERY_DIR/architecture-summary.txt"

echo "=== Port Mappings ===" >> "$DISCOVERY_DIR/architecture-summary.txt"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -v "PORTS" >> "$DISCOVERY_DIR/architecture-summary.txt"
echo "" >> "$DISCOVERY_DIR/architecture-summary.txt"

echo ""
echo "=== ARCHITECTURE CAPTURE COMPLETE ==="
echo "All data captured in: $DISCOVERY_DIR"
echo "Key files:"
echo "- containers.txt: Container overview"
echo "- container-details/: Individual container details"
echo "- compose-files/: Docker Compose configurations"
echo "- volumes.txt: Volume mappings"
echo "- networks.txt: Network configuration"
echo "- architecture-summary.txt: High-level architecture overview"
echo ""
echo "OnlyOffice DocSpace is accessible at: http://$(hostname -I | awk '{print $1}')"