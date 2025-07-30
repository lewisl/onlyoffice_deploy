# OnlyOffice Document Server Deployment Automation Project - UPDATED

## Critical Docker Architecture Requirements

### Docker Expertise Requirement
**Claude Code must be a Docker expert** to handle the complex containerized architecture of OnlyOffice, which involves:
- **28+ containers** across multiple docker-compose configurations
- **Container-to-host filesystem mapping** for persistent data
- **Container networking** for SSL certificate access
- **Container lifecycle management** without exposing Docker complexity to administrators

### Container vs. Host Filesystem Clarity
**CRITICAL**: Always distinguish between:
- **Container filesystem paths** (inside Docker containers)
- **Host filesystem paths** (on the Digital Ocean droplet OS)
- **Volume mappings** that bridge container and host filesystems

## Updated Technical Specifications

### SSL Certificate Management Architecture
**Problem**: SSL certificates must be accessible to nginx running **inside** the OnlyOffice container, not just the host OS.

**Solution Strategy**:
1. **Host-side certificate management**: Use certbot/Let's Encrypt on the host OS to manage certificates at `/etc/letsencrypt/`
2. **Container access via symbolic links**: Create symbolic links from container nginx configuration to host certificate paths
3. **Volume mapping verification**: Ensure docker-compose.yml properly maps certificate paths into containers
4. **Testing requirement**: Claude Code must verify certificate accessibility from within the container, not just host OS

**Research Tasks**:
- Analyze OnlyOffice container nginx configuration
- Identify correct volume mapping for certificate access
- Test certificate renewal without container restarts
- Verify SSL functionality from container perspective

### Digital Ocean Encrypted Block Storage Integration
**Reference**: https://helpcenter.onlyoffice.com/docspace/configuration/docspace-encryption-at-rest.aspx

**Problem**: Internet advice often suggests post-installation modification of container config files with hardcoded paths - this is fragile and brittle.

**Better Approach**:
1. **Pre-installation configuration**: Modify docker-compose configurations BEFORE container deployment
2. **Proper volume mapping**: Use Docker volume syntax to map encrypted block storage to container paths
3. **Environment variable configuration**: Use OnlyOffice environment variables where possible instead of direct file modification
4. **Validation testing**: Ensure encrypted storage is properly mounted and accessible within containers

**Encrypted Storage Mapping Strategy**:
```
Host Encrypted Block Storage → Container Internal Paths
/encrypted-storage/onlyoffice-data → /var/www/onlyoffice/Data
/encrypted-storage/mysql-data → /var/lib/mysql  
/encrypted-storage/logs → /var/log/onlyoffice
/encrypted-storage/cache → /var/lib/onlyoffice
```

### Docker Management Abstraction Scripts
**Requirement**: Complete Docker abstraction - administrator never needs Docker knowledge.

**Required Scripts with Docker Wrapping**:

#### Container Status Management
- `onlyoffice-status.sh` - Check status of all OnlyOffice containers
- `onlyoffice-status.sh <container-name-or-id>` - Check individual container status
- Output: Human-readable status, not raw Docker output

#### Container Lifecycle Management  
- `onlyoffice-start.sh` - Start all containers in dependency order
- `onlyoffice-start.sh <container-name>` - Start specific container
- `onlyoffice-stop.sh` - Stop all containers in reverse dependency order
- `onlyoffice-stop.sh <container-name>` - Stop specific container  
- `onlyoffice-restart.sh` - Restart all containers with proper ordering
- `onlyoffice-restart.sh <container-name>` - Restart specific container

#### Container Health and Diagnostics
- `onlyoffice-health.sh` - Comprehensive health check of all containers and services
- `onlyoffice-logs.sh <container-name>` - View logs from specific container
- `onlyoffice-exec.sh <container-name> <command>` - Execute commands within containers
- `onlyoffice-inspect.sh <container-name>` - Detailed container configuration and status

#### Documentation Through Scripts
**Each script serves as executable documentation** containing:
- Verified correct Docker commands
- Proper error handling and validation
- Human-readable output and error messages
- No Docker knowledge required from administrator

## Updated Project Phases

### Phase 1: Docker Architecture Discovery
**Enhanced Objectives**:
1. **Container topology mapping** - Identify all containers, their purposes, and interdependencies
2. **Volume mapping analysis** - Document all host-to-container filesystem mappings
3. **Network configuration discovery** - Understand container networking and port mappings
4. **Configuration file locations** - Map container config files to host filesystem locations
5. **Docker-compose structure analysis** - Understand the complete orchestration setup

**Docker-Specific Deliverables**:
- Complete container dependency diagram
- Volume mapping inventory (host paths → container paths)
- Network topology documentation
- docker-compose.yml analysis and documentation

### Phase 2: Encrypted Storage Integration (Docker-Aware)
**Enhanced Approach**:
1. **Pre-deployment docker-compose modification** - Configure encrypted storage mappings before container creation
2. **Volume mapping validation** - Ensure encrypted storage is properly accessible within containers
3. **Container data migration** - Move existing container data to encrypted storage with proper permissions
4. **Docker volume management** - Use Docker volume commands for proper mounting and permissions

### Phase 3: Container Lifecycle Management (Complete Docker Abstraction)
**Enhanced Deliverables**:
- Complete set of Docker-wrapping scripts (as specified above)
- Dependency-aware container orchestration
- Container health monitoring from within containers
- Log aggregation across all containers
- Container-aware troubleshooting tools

### Phase 4: SSL Automation (Container-Integrated)
**Enhanced Approach**:
1. **Host-side certificate management** with certbot/Let's Encrypt
2. **Container volume mapping** for certificate access
3. **Nginx configuration within containers** for SSL termination
4. **Certificate renewal automation** without container disruption
5. **SSL validation from container perspective**

### Phase 5: Docker-Abstracted Operations Documentation
**Enhanced Focus**:
- All operational procedures hide Docker complexity
- Scripts serve as executable documentation
- Troubleshooting guides focus on service-level issues, not Docker issues
- Container management procedures that don't require Docker knowledge

## Critical Success Criteria Updates

### Docker Expertise Validation
- Claude Code must demonstrate understanding of OnlyOffice's complex container architecture
- All solutions must work within the Docker containerized context
- Container vs. host filesystem operations must be clearly distinguished
- SSL and storage solutions must function correctly within containers

### Administrator Experience
- **Zero Docker knowledge required** - all Docker operations wrapped in intuitive scripts
- **Service-focused interface** - administrator thinks in terms of OnlyOffice services, not containers
- **Executable documentation** - scripts contain and demonstrate correct procedures
- **Robust error handling** - meaningful error messages that don't require Docker debugging skills

### Technical Validation Requirements
1. **SSL certificates accessible and functional within OnlyOffice containers**
2. **Encrypted block storage properly mounted and accessible within containers**
3. **Container orchestration working with proper dependency management**
4. **All administrative tasks achievable without direct Docker commands**
5. **Certificate renewal and storage management working without container disruption**

## Development Environment Requirements

### Docker Testing Environment
- Full Docker and docker-compose installation on DO droplet
- Ability to test container networking, volume mounting, and orchestration
- Access to container internals for configuration verification
- Testing of certificate access from within containers

### Validation Approach
- **Container-internal testing** - Verify functionality from within containers, not just host
- **End-to-end SSL testing** - Ensure certificates work with OnlyOffice's internal nginx
- **Storage persistence testing** - Verify data survives container restarts and recreations
- **Script functionality testing** - Ensure all administrative scripts work without Docker knowledge

This updated approach ensures that the final deployment toolkit properly handles OnlyOffice's containerized architecture while completely abstracting Docker complexity from the system administrator.