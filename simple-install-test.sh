#!/bin/bash

# Simple OnlyOffice Installation Test
# This creates a minimal working installation for testing our management scripts

set -e

echo "=== Simple OnlyOffice DocSpace Installation Test ==="
echo "This will create a minimal installation for testing our management scripts"
echo ""

# Check if we're root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Create installation directory
echo "Creating installation structure..."
mkdir -p /app/onlyoffice/config/nginx

# Create basic environment file
cat > /app/onlyoffice/.env << 'EOF'
PRODUCT=docspace
NETWORK_NAME=onlyoffice
EXTERNAL_PORT=80
PROXY_HOST=onlyoffice-proxy
ROUTER_HOST=onlyoffice-router
MYSQL_HOST=onlyoffice-mysql-server
MYSQL_USER=onlyoffice
MYSQL_PASSWORD=onlyoffice_password
MYSQL_DATABASE=onlyoffice
MYSQL_ROOT_PASSWORD=root_password
DOCUMENT_SERVER_JWT_SECRET=jwt_secret_key
DOCUMENT_SERVER_JWT_HEADER=Authorization
REGISTRY=
REPO=onlyoffice
DOCKER_IMAGE_PREFIX=docspace
DOCKER_TAG=3.2.1.1
PROXY_IMAGE_NAME=nginx:latest
EOF

# Create network
echo "Creating Docker network..."
docker network create onlyoffice 2>/dev/null || echo "Network already exists"

# Pull essential images
echo "Pulling Docker images..."
docker pull mysql:8.3.0
docker pull nginx:latest  
docker pull onlyoffice/docspace-api:3.2.1.1
docker pull onlyoffice/docspace-studio:3.2.1.1
docker pull onlyoffice/documentserver:9.0.3.1

# Create basic nginx config
cat > /app/onlyoffice/config/nginx/onlyoffice-proxy.conf << 'EOF'
upstream backend {
    server onlyoffice-router:8092;
}

server {
    listen 80;
    server_name _;
    
    client_max_body_size 4G;
    
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Create basic docker-compose file for testing
cat > /app/onlyoffice/test-compose.yml << 'EOF'
version: '3.8'

networks:
  default:
    name: onlyoffice
    external: true

services:
  onlyoffice-mysql-server:
    image: mysql:8.3.0
    container_name: onlyoffice-mysql-server
    environment:
      - MYSQL_ROOT_PASSWORD=root_password
      - MYSQL_DATABASE=onlyoffice
      - MYSQL_USER=onlyoffice
      - MYSQL_PASSWORD=onlyoffice_password
    volumes:
      - /mnt/docspace_data/mysql_data:/var/lib/mysql
    restart: always
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 30s
      timeout: 10s
      retries: 5
      
  onlyoffice-proxy:
    image: nginx:latest
    container_name: onlyoffice-proxy
    ports:
      - "80:80"
    volumes:
      - ./config/nginx/onlyoffice-proxy.conf:/etc/nginx/conf.d/default.conf
      - /mnt/docspace_data/log_data:/var/log/nginx
    depends_on:
      - onlyoffice-mysql-server
    restart: always
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3
      
  onlyoffice-api:
    image: onlyoffice/docspace-api:3.2.1.1
    container_name: onlyoffice-api
    environment:
      - MYSQL_HOST=onlyoffice-mysql-server
      - MYSQL_DATABASE=onlyoffice
      - MYSQL_USER=onlyoffice
      - MYSQL_PASSWORD=onlyoffice_password
    volumes:
      - /mnt/docspace_data/app_data:/app/onlyoffice/data
      - /mnt/docspace_data/log_data:/var/log/onlyoffice
    depends_on:
      - onlyoffice-mysql-server
    restart: always
    
  onlyoffice-studio:
    image: onlyoffice/docspace-studio:3.2.1.1
    container_name: onlyoffice-studio
    environment:
      - MYSQL_HOST=onlyoffice-mysql-server
      - MYSQL_DATABASE=onlyoffice
      - MYSQL_USER=onlyoffice
      - MYSQL_PASSWORD=onlyoffice_password
    volumes:
      - /mnt/docspace_data/app_data:/app/onlyoffice/data
      - /mnt/docspace_data/log_data:/var/log/onlyoffice
    depends_on:
      - onlyoffice-mysql-server
      - onlyoffice-api
    restart: always
EOF

echo "Installation structure created successfully!"
echo ""
echo "To start the test installation:"
echo "  docker compose -f /app/onlyoffice/test-compose.yml up -d"
echo ""
echo "To test with our management scripts:"
echo "  ./onlyoffice-status.sh"
echo "  ./onlyoffice-health.sh"
echo ""
echo "Note: This is a minimal test setup, not a full OnlyOffice installation"