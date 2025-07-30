# OnlyOffice DocSpace SSL Architecture Analysis

## SSL Setup Process Discovered

### 1. SSL Configuration Script
**Location**: `/app/onlyoffice/config/docspace-ssl-setup`

**Capabilities**:
- Automatic Let's Encrypt SSL certificates
- Custom certificate installation
- Switch between HTTP and HTTPS configurations
- Automatic certificate renewal setup

### 2. Docker Compose Configuration Switch

**HTTP Configuration**: `/app/onlyoffice/proxy.yml`
- Exposes only port 80
- Uses `onlyoffice-proxy.conf` (HTTP only)
- No SSL certificates mounted

**HTTPS Configuration**: `/app/onlyoffice/proxy-ssl.yml`
- Exposes ports 80, 443 (TCP and UDP for HTTP/3)
- Uses `onlyoffice-proxy-ssl.conf` (HTTPS with HTTP redirect)
- Mounts SSL certificates into container
- Mounts DH parameters for strong SSL

### 3. Container Volume Mappings for SSL

When SSL is enabled, the following are mounted into the nginx proxy container:
```yaml
volumes:
  - ${CERTIFICATE_PATH}:/usr/local/share/ca-certificates/tls.crt
  - ${CERTIFICATE_KEY_PATH}:/etc/ssl/private/tls.key
  - ${DHPARAM_PATH}:/etc/ssl/certs/dhparam.pem
```

### 4. Nginx Configuration Changes

**HTTP Configuration** (`onlyoffice-proxy.conf`):
- Single server block listening on port 80
- Direct proxy pass to router

**HTTPS Configuration** (`onlyoffice-proxy-ssl.conf`):
- HTTP server block that redirects all traffic to HTTPS
- Localhost HTTP server block for internal health checks
- HTTPS server block with:
  - SSL/TLS 1.2 and 1.3 support
  - HTTP/2 and HTTP/3 (QUIC) support
  - Strong SSL ciphers and security headers
  - OCSP stapling support (optional)

### 5. Certificate Management Process

1. **SSL Script Execution**:
   - Validates certificate files
   - Generates DH parameters (2048-bit)
   - Updates environment variables in `.env`
   - Modifies container configurations
   - Restarts affected containers

2. **Container Integration**:
   - Certificates accessible within containers via volume mounts
   - Document Server gets extra CA certificates
   - All services can validate SSL connections

### 6. Key Architecture Insights

**Container-to-Host SSL Certificate Access**: 
- Certificates managed on host filesystem
- Mounted into containers via Docker volumes
- Multiple containers can access same certificates

**Multi-Service SSL Integration**:
- Not just the proxy uses certificates
- Document Server also gets certificate access
- API services can validate SSL connections

**Certificate Renewal Process**:
- Script creates automatic renewal cron jobs
- Containers don't need restart for certificate renewal
- Volume mounts provide live certificate updates

## SSL Architecture Summary

OnlyOffice DocSpace implements SSL through:

1. **Host-side certificate management** (via script)
2. **Container volume mapping** for certificate access  
3. **Nginx proxy SSL termination** with HTTP redirect
4. **Multi-container certificate distribution** 
5. **Automatic renewal integration** with cron

This matches the directive_v2.md requirements for "Container volume mapping for certificate access" and "SSL validation from container perspective".

## Container Dependencies for SSL

When SSL is enabled:
- `onlyoffice-proxy` - SSL termination and HTTP redirect
- `onlyoffice-document-server` - Uses certificates for validation
- `onlyoffice-router` - Backend routing (unchanged)
- All API services continue to use internal HTTP

The SSL architecture successfully implements the "Container-integrated SSL" approach specified in the directive.