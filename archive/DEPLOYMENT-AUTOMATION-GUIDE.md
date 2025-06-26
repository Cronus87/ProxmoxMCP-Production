# Proxmox MCP Server - Deployment Automation Guide

## Overview

This guide provides comprehensive deployment automation for the Proxmox MCP Server, including local builds, health monitoring, and update mechanisms that don't rely on GitHub Actions.

## Root Cause Analysis

### Issue Identified
The Docker container was not running due to:
1. **Missing Docker Image**: The image `ghcr.io/your-username/fullproxmoxmcp:latest` was a placeholder and never built/pushed to GitHub Container Registry
2. **Broken GitHub Actions**: The CI/CD pipeline was not functional
3. **Caddyfile Configuration Issues**: Used unsupported directives causing the reverse proxy to fail

### Solution Implemented
1. **Local Image Building**: Build Docker images locally instead of relying on external registry
2. **Fixed Configuration**: Updated docker-compose.yml and Caddyfile with working configurations
3. **Deployment Automation**: Created comprehensive scripts for build, deploy, monitor, and update operations

## Scripts Overview

### 1. Local Build and Deploy Script (`deploy/local-build-deploy.sh`)

**Purpose**: Complete local build and deployment without external dependencies

**Features**:
- Builds Docker image locally from source
- Creates backups before deployment
- Sets up deployment directory structure
- Fixes configuration issues automatically
- Includes rollback capability
- Comprehensive verification

**Usage**:
```bash
# Full deployment
sudo ./deploy/local-build-deploy.sh

# Build only
sudo ./deploy/local-build-deploy.sh build

# Verify existing deployment
sudo ./deploy/local-build-deploy.sh verify

# Create backup
sudo ./deploy/local-build-deploy.sh backup

# Rollback to previous version
sudo ./deploy/local-build-deploy.sh rollback
```

### 2. Health Monitoring Script (`deploy/monitor-health.sh`)

**Purpose**: Continuous monitoring and health checking

**Features**:
- Container status monitoring
- Endpoint accessibility checks
- Resource usage monitoring
- Auto-healing capabilities
- Watch mode for continuous monitoring
- Logging to file

**Usage**:
```bash
# Quick health check
sudo ./deploy/monitor-health.sh

# Continuous monitoring (every 60 seconds)
sudo ./deploy/monitor-health.sh watch

# Auto-heal if issues detected
sudo ./deploy/monitor-health.sh heal

# Show logs
sudo ./deploy/monitor-health.sh logs 100

# Restart services
sudo ./deploy/monitor-health.sh restart
```

### 3. Update System Script (`deploy/update-system.sh`)

**Purpose**: Automated updates and version management

**Features**:
- Git repository updates
- Image rebuilding
- Testing before deployment
- Rolling updates
- Automatic rollback on failure
- Old image cleanup

**Usage**:
```bash
# Full update process
sudo ./deploy/update-system.sh update

# Check current status
sudo ./deploy/update-system.sh status

# Update code only
sudo ./deploy/update-system.sh code

# Rollback if needed
sudo ./deploy/update-system.sh rollback
```

## Deployment Process

### Initial Deployment

1. **Clone Repository** (if not already done):
```bash
git clone <repository-url> /opt/proxmox-mcp-source
cd /opt/proxmox-mcp-source
```

2. **Run Initial Deployment**:
```bash
sudo ./deploy/local-build-deploy.sh
```

3. **Verify Deployment**:
```bash
sudo ./deploy/monitor-health.sh
```

### Configuration

The deployment creates `/opt/proxmox-mcp/.env` with default settings. Update this file with your actual configuration:

```bash
sudo nano /opt/proxmox-mcp/.env
```

Key settings to update:
- `SSH_HOST`: Your Proxmox server IP/hostname
- `PROXMOX_HOST`: Your Proxmox server IP/hostname
- `PROXMOX_TOKEN_VALUE`: Your actual Proxmox API token
- `SSH_USER`: SSH username for Proxmox access

### Service Endpoints

After successful deployment:
- **Web UI**: http://your-server-ip/docs
- **Health Check**: http://your-server-ip/health
- **Direct Access**: http://your-server-ip:8080
- **API Endpoint**: http://your-server-ip/api/mcp

## Ongoing Operations

### Daily Monitoring

Set up a cron job for regular health checks:
```bash
# Add to root crontab
sudo crontab -e

# Add this line for hourly health checks
0 * * * * /opt/proxmox-mcp-source/deploy/monitor-health.sh >> /var/log/proxmox-mcp-monitor.log 2>&1
```

### Weekly Updates

Set up automated weekly updates:
```bash
# Add to root crontab for Sunday 2 AM updates
0 2 * * 0 /opt/proxmox-mcp-source/deploy/update-system.sh update >> /var/log/proxmox-mcp-update.log 2>&1
```

### Log Management

Important log locations:
- **Container Logs**: `cd /opt/proxmox-mcp && docker-compose logs`
- **Monitor Logs**: `/var/log/proxmox-mcp-monitor.log`
- **Update Logs**: `/var/log/proxmox-mcp-update.log`

## Troubleshooting

### Common Issues

1. **Container Won't Start**:
```bash
# Check logs
cd /opt/proxmox-mcp && sudo docker-compose logs

# Try rebuilding
sudo ./deploy/local-build-deploy.sh build
```

2. **Services Not Accessible**:
```bash
# Check container status
sudo docker ps

# Check endpoints
sudo ./deploy/monitor-health.sh endpoints

# Check firewall
sudo ufw status
```

3. **High Resource Usage**:
```bash
# Check resource usage
sudo ./deploy/monitor-health.sh resources

# Restart if needed
sudo ./deploy/monitor-health.sh restart
```

### Emergency Procedures

**If deployment fails**:
```bash
# Rollback to previous version
sudo ./deploy/local-build-deploy.sh rollback
```

**If update fails**:
```bash
# Rollback update
sudo ./deploy/update-system.sh rollback
```

**If services are unresponsive**:
```bash
# Auto-heal attempt
sudo ./deploy/monitor-health.sh heal

# Manual restart
cd /opt/proxmox-mcp && sudo docker-compose restart
```

## Security Considerations

1. **File Permissions**: Scripts automatically set proper permissions
2. **Network Exposure**: Services are bound to localhost by default
3. **API Security**: Configure Proxmox API tokens with minimal required permissions
4. **SSH Access**: Use key-based authentication for SSH connections

## Backup and Recovery

### Automated Backups
- Backups are created automatically before deployments
- Stored in `/opt/proxmox-mcp-backups/`
- Automatic cleanup keeps only 5 most recent backups

### Manual Backup
```bash
sudo ./deploy/local-build-deploy.sh backup
```

### Recovery
```bash
# List available backups
ls -la /opt/proxmox-mcp-backups/

# Manual restore (replace with actual backup name)
sudo cp -r /opt/proxmox-mcp-backups/backup-20241225_120000 /opt/proxmox-mcp
cd /opt/proxmox-mcp && sudo docker-compose up -d
```

## Performance Optimization

### Resource Limits
The docker-compose.yml includes resource limits:
- CPU: 2 cores max, 0.5 cores reserved
- Memory: 2GB max, 512MB reserved

### Monitoring
Use the resource monitoring to track performance:
```bash
sudo ./deploy/monitor-health.sh resources
```

## Integration with Existing Systems

### Systemd Integration
The deployment can optionally set up systemd services for automatic startup.

### Monitoring Integration
The health monitoring script outputs structured logs that can be integrated with external monitoring systems.

### Proxy Integration
The Caddy reverse proxy can be configured for external domains and SSL termination.

## Conclusion

This deployment automation provides:
- ✅ Reliable local builds without external dependencies
- ✅ Comprehensive health monitoring and auto-healing
- ✅ Safe update mechanisms with automatic rollback
- ✅ Backup and recovery procedures
- ✅ Troubleshooting and emergency procedures

The solution eliminates dependency on GitHub Actions and provides a robust, self-contained deployment system suitable for production use.