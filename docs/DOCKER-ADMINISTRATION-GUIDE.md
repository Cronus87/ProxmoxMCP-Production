# Docker Administration Guide - Proxmox MCP System

**Comprehensive Docker management across Proxmox host and LXC containers using MCP tools**

---

## Table of Contents

1. [Docker Ecosystem Overview](#docker-ecosystem-overview)
2. [Complete Infrastructure Mapping](#complete-infrastructure-mapping)
3. [Container-by-Container Management](#container-by-container-management)
4. [Docker Image Lifecycle Management](#docker-image-lifecycle-management)
5. [Practical Administration Examples](#practical-administration-examples)
6. [Security and Compliance](#security-and-compliance)
7. [Performance Monitoring](#performance-monitoring)
8. [Integration with Proxmox](#integration-with-proxmox)
9. [Troubleshooting Guide](#troubleshooting-guide)
10. [Advanced Operations](#advanced-operations)

---

## Docker Ecosystem Overview

### Infrastructure Architecture

Our Proxmox environment runs a distributed Docker ecosystem:

```
Proxmox Host (pve)
├── Docker Engine (Host Level)
│   ├── proxmox-mcp-server (Production)
│   ├── n8n (Automation)
│   ├── ombi (Media Management)
│   ├── caddy (Reverse Proxy)
│   └── 12 orphaned build images
│
├── LXC Container 100 (ombi-server)
│   ├── ombi:latest (Active)
│   └── hello-world:latest (Test)
│
├── LXC Container 102 (amp-game-servers)
│   ├── cubecoders/amp:latest (2.8GB)
│   ├── cubecoders/ampbase:latest (1.2GB)
│   ├── cubecoders/amptemplates:latest (1.8GB)
│   └── Total: 5.8GB storage
│
├── LXC Container 103 (homeassistant)
│   ├── homeassistant/home-assistant:latest (1.8GB)
│   ├── eclipse-mosquitto:latest (13MB)
│   ├── portainer/portainer-ce:latest (1.7GB)
│   └── Total: 3.5GB storage
│
└── LXC Container 154 (llm-server)
    ├── ollama/ollama:latest (2.1GB)
    ├── ghcr.io/open-webui/open-webui:main (1.9GB)
    ├── postgres:16-alpine (2.6GB)
    ├── redis:7-alpine (2.0GB)
    └── Total: 8.6GB storage
```

### Total Docker Footprint
- **Host Docker**: 4 active containers + 12 orphaned images
- **LXC Containers**: 4 containers with Docker ecosystems
- **Total Images**: 20+ Docker images across infrastructure
- **Total Storage**: ~25GB+ Docker storage usage

---

## Complete Infrastructure Mapping

### Automated Docker Discovery

Use the MCP system to map your entire Docker ecosystem:

```bash
# Map all Docker instances across infrastructure
claude mcp invoke proxmox-production execute_command \
  --command "docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}' && echo -e '\n--- LXC CONTAINERS ---' && for ct in 100 102 103 154; do echo -e '\n=== Container $ct ==='; pct exec $ct -- docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}' 2>/dev/null || echo 'No Docker or not running'; done"
```

### Real Infrastructure Snapshot

**Proxmox Host Docker Images:**
```
REPOSITORY              TAG     SIZE    CREATED
proxmox-mcp-server     latest  187MB   2024-12-26 15:23:16
n8n                    latest  419MB   2024-12-20 10:45:32
ombi                   latest  394MB   2024-12-18 08:12:45
caddy                  latest  58.2MB  2024-12-15 14:30:12
+ 12 orphaned build images from development
```

**LXC Container 100 (ombi-server):**
```
REPOSITORY    TAG     SIZE    CREATED
ombi         latest  394MB   2024-12-20 11:15:23
hello-world  latest  13.3kB  2024-12-19 16:42:10
```

**LXC Container 102 (amp-game-servers):**
```
REPOSITORY                   TAG     SIZE    CREATED
cubecoders/amp              latest  2.8GB   2024-12-18 09:30:45
cubecoders/ampbase          latest  1.2GB   2024-12-18 09:25:12
cubecoders/amptemplates     latest  1.8GB   2024-12-18 09:33:22
```

**LXC Container 103 (homeassistant):**
```
REPOSITORY                      TAG     SIZE    CREATED
homeassistant/home-assistant   latest  1.8GB   2024-12-20 14:22:33
eclipse-mosquitto              latest  13MB    2024-12-19 12:45:18
portainer/portainer-ce         latest  1.7GB   2024-12-18 16:15:42
```

**LXC Container 154 (llm-server):**
```
REPOSITORY                        TAG          SIZE    CREATED
ollama/ollama                    latest       2.1GB   2024-12-21 08:30:15
ghcr.io/open-webui/open-webui   main         1.9GB   2024-12-20 19:45:33
postgres                        16-alpine    2.6GB   2024-12-19 11:20:18
redis                           7-alpine     2.0GB   2024-12-19 11:22:45
```

---

## Container-by-Container Management

### Managing Host Docker

**List containers and images:**
```bash
# Active containers
docker ps -a

# All images with sizes
docker images

# System usage
docker system df
```

**Container operations:**
```bash
# Start/stop containers
docker start proxmox-mcp-server
docker stop n8n
docker restart ombi

# View logs
docker logs -f caddy
docker logs --tail 50 proxmox-mcp-server

# Execute commands in containers
docker exec -it n8n /bin/bash
```

### Managing LXC Container Docker

**Execute Docker commands in LXC containers:**

```bash
# Container 100 (ombi-server)
pct exec 100 -- docker ps -a
pct exec 100 -- docker images
pct exec 100 -- docker logs ombi

# Container 102 (amp-game-servers)
pct exec 102 -- docker ps -a
pct exec 102 -- docker exec -it amp-container /bin/bash

# Container 103 (homeassistant)
pct exec 103 -- docker ps -a
pct exec 103 -- docker logs homeassistant

# Container 154 (llm-server)
pct exec 154 -- docker ps -a
pct exec 154 -- docker logs ollama
```

**Batch operations across all containers:**
```bash
# Stop all Docker containers across infrastructure
for ct in 100 102 103 154; do
  echo "=== Stopping Docker in Container $ct ==="
  pct exec $ct -- docker stop $(docker ps -q) 2>/dev/null || echo "No containers running"
done

# Start all Docker containers
for ct in 100 102 103 154; do
  echo "=== Starting Docker in Container $ct ==="
  pct exec $ct -- docker start $(docker ps -aq) 2>/dev/null || echo "No containers to start"
done
```

---

## Docker Image Lifecycle Management

### Image Updates and Maintenance

**Update all images on host:**
```bash
# Pull latest versions
docker pull proxmox-mcp-server:latest
docker pull n8n:latest
docker pull ombi:latest
docker pull caddy:latest

# Recreate containers with new images
docker-compose down && docker-compose up -d
```

**Update images in LXC containers:**
```bash
# Update Home Assistant
pct exec 103 -- docker pull homeassistant/home-assistant:latest
pct exec 103 -- docker-compose down && docker-compose up -d

# Update LLM server stack
pct exec 154 -- docker pull ollama/ollama:latest
pct exec 154 -- docker pull ghcr.io/open-webui/open-webui:main
pct exec 154 -- docker-compose restart
```

### Image Cleanup Operations

**Remove orphaned images:**
```bash
# Host cleanup
docker image prune -f
docker system prune -a -f

# LXC container cleanup
for ct in 100 102 103 154; do
  echo "=== Cleaning Container $ct ==="
  pct exec $ct -- docker image prune -f
  pct exec $ct -- docker system prune -f
done
```

**Identify and remove unused images:**
```bash
# Find orphaned images
docker images --filter "dangling=true"

# Remove specific orphaned images
docker rmi $(docker images --filter "dangling=true" -q)
```

### Build and Deployment

**Build custom images:**
```bash
# Build on host
docker build -t proxmox-mcp-server:v2.0 .

# Build in LXC container
pct exec 154 -- docker build -t custom-llm-server:latest /opt/llm-server/
```

**Deploy across infrastructure:**
```bash
# Deploy to multiple containers
for ct in 100 102 103; do
  echo "=== Deploying to Container $ct ==="
  # Copy image or use registry
  docker save custom-app:latest | pct exec $ct -- docker load
done
```

---

## Practical Administration Examples

### Real-world Operations Using MCP

**Example 1: Restart All Media Services**
```bash
# Through MCP
claude mcp invoke proxmox-production execute_command \
  --command "docker restart ombi && pct exec 100 -- docker restart ombi && echo 'Media services restarted'"
```

**Example 2: Check Resource Usage Across All Containers**
```bash
# Get comprehensive resource usage
claude mcp invoke proxmox-production execute_command \
  --command "echo '=== HOST DOCKER STATS ===' && docker stats --no-stream && echo -e '\n=== LXC CONTAINER STATS ===' && for ct in 100 102 103 154; do echo -e '\n--- Container $ct ---'; pct exec $ct -- docker stats --no-stream 2>/dev/null || echo 'No Docker containers running'; done"
```

**Example 3: Mass Configuration Update**
```bash
# Update environment variables across all containers
claude mcp invoke proxmox-production execute_command \
  --command "docker exec proxmox-mcp-server printenv | grep -E '^(PROXMOX|MCP)' && for ct in 100 102 103 154; do echo -e '\n=== Container $ct Environment ==='; pct exec $ct -- docker exec $(docker ps -q | head -1) printenv 2>/dev/null | head -10 || echo 'No running containers'; done"
```

### Automated Maintenance Scripts

**Daily health check script:**
```bash
#!/bin/bash
# /opt/scripts/docker-health-check.sh

echo "=== DOCKER HEALTH CHECK $(date) ==="

# Host Docker
echo "HOST DOCKER STATUS:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# LXC Docker
for ct in 100 102 103 154; do
  echo -e "\n=== LXC Container $ct ==="
  if pct status $ct | grep -q running; then
    pct exec $ct -- docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No Docker or containers"
  else
    echo "Container not running"
  fi
done

# Resource usage
echo -e "\n=== RESOURCE USAGE ==="
docker system df
echo -e "\nTotal Docker processes: $(docker ps -q | wc -l)"
```

**Weekly cleanup script:**
```bash
#!/bin/bash
# /opt/scripts/docker-cleanup.sh

echo "=== DOCKER CLEANUP $(date) ==="

# Host cleanup
echo "Cleaning host Docker..."
docker image prune -f
docker container prune -f
docker volume prune -f
docker network prune -f

# LXC cleanup
for ct in 100 102 103 154; do
  echo "Cleaning LXC Container $ct..."
  if pct status $ct | grep -q running; then
    pct exec $ct -- docker image prune -f 2>/dev/null || echo "Cleanup failed"
    pct exec $ct -- docker container prune -f 2>/dev/null
  fi
done

echo "Cleanup completed"
```

---

## Security and Compliance

### Container Security Assessment

**Security scanning:**
```bash
# Scan images for vulnerabilities
docker scout cves proxmox-mcp-server:latest

# Check for rootless configuration
docker info | grep -i rootless

# Verify user permissions
docker exec proxmox-mcp-server whoami
```

**Security best practices:**
```bash
# Check for privileged containers
docker ps --filter "label=privileged=true"

# Verify network isolation
docker network ls
docker network inspect bridge

# Check resource limits
docker stats --no-stream
```

### Access Control and Permissions

**Verify claude-user permissions:**
```bash
# Check Docker group membership
groups claude-user

# Test Docker access
sudo -u claude-user docker ps

# Verify restricted permissions
sudo -u claude-user docker exec proxmox-mcp-server cat /etc/passwd
```

### Security Monitoring

**Monitor Docker daemon:**
```bash
# Check Docker daemon logs
journalctl -u docker.service --since "1 hour ago"

# Monitor container events
docker events --since "1 hour ago"

# Check for suspicious activity
docker logs --since "1 hour ago" $(docker ps -q)
```

---

## Performance Monitoring

### Resource Usage Analysis

**System-wide Docker resource usage:**
```bash
# Get comprehensive resource view
claude mcp invoke proxmox-production execute_command \
  --command "echo '=== HOST DOCKER RESOURCES ===' && docker stats --no-stream && echo -e '\n=== HOST DISK USAGE ===' && docker system df -v && echo -e '\n=== LXC DOCKER RESOURCES ===' && for ct in 100 102 103 154; do echo -e '\n--- Container $ct ---'; pct exec $ct -- docker stats --no-stream 2>/dev/null | head -5 || echo 'No Docker stats available'; done"
```

### Performance Optimization

**Identify resource-heavy containers:**
```bash
# Sort by CPU usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

# Find largest images
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | sort -k3 -hr
```

**Optimize container performance:**
```bash
# Set resource limits
docker update --memory 512m --cpus 1.0 proxmox-mcp-server

# Restart containers with new limits
docker-compose down && docker-compose up -d
```

### Monitoring Dashboards

**Create monitoring data:**
```bash
# Generate performance report
cat << 'EOF' > /opt/docker-performance-report.sh
#!/bin/bash
echo "=== DOCKER PERFORMANCE REPORT $(date) ==="
echo "HOST CONTAINERS:"
docker stats --no-stream --format "{{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}} NET={{.NetIO}}"

echo -e "\nLXC CONTAINERS:"
for ct in 100 102 103 154; do
  if pct status $ct | grep -q running; then
    echo "Container $ct:"
    pct exec $ct -- docker stats --no-stream --format "  {{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}" 2>/dev/null | head -3
  fi
done

echo -e "\nDISK USAGE:"
docker system df
EOF

chmod +x /opt/docker-performance-report.sh
```

---

## Integration with Proxmox

### LXC Container Management

**Container lifecycle with Docker:**
```bash
# Start LXC container and Docker services
pct start 103
sleep 10
pct exec 103 -- systemctl start docker
pct exec 103 -- docker-compose up -d

# Stop Docker services before LXC shutdown
pct exec 103 -- docker-compose down
pct exec 103 -- systemctl stop docker
pct stop 103
```

### Backup and Recovery

**Backup Docker volumes:**
```bash
# Backup host Docker volumes
docker run --rm -v proxmox-mcp-data:/data -v /backup:/backup alpine tar czf /backup/proxmox-mcp-backup-$(date +%Y%m%d).tar.gz /data

# Backup LXC container Docker volumes
pct exec 154 -- docker run --rm -v llm-data:/data -v /backup:/backup alpine tar czf /backup/llm-server-backup-$(date +%Y%m%d).tar.gz /data
```

**Disaster recovery:**
```bash
# Restore Docker volumes
docker run --rm -v proxmox-mcp-data:/data -v /backup:/backup alpine tar xzf /backup/proxmox-mcp-backup-20241226.tar.gz -C /

# Restore LXC Docker volumes
pct exec 154 -- docker run --rm -v llm-data:/data -v /backup:/backup alpine tar xzf /backup/llm-server-backup-20241226.tar.gz -C /
```

### Proxmox API Integration

**Monitor containers through Proxmox API:**
```bash
# Get container status
claude mcp invoke proxmox-production vm_status --vmid 103 --node pve

# List all containers
claude mcp invoke proxmox-production list_vms
```

---

## Troubleshooting Guide

### Common Issues and Solutions

**1. Docker daemon not responding in LXC**
```bash
# Check if Docker is running
pct exec 154 -- systemctl status docker

# Restart Docker daemon
pct exec 154 -- systemctl restart docker

# Check for kernel compatibility
pct exec 154 -- docker info | grep -i kernel
```

**2. Container networking issues**
```bash
# Check network configuration
docker network ls
docker network inspect bridge

# Test container connectivity
docker exec proxmox-mcp-server ping -c 3 8.8.8.8
```

**3. Permission denied errors**
```bash
# Check user permissions
groups claude-user

# Verify Docker socket permissions
ls -la /var/run/docker.sock

# Fix permissions
sudo usermod -aG docker claude-user
```

**4. Storage issues**
```bash
# Check Docker storage usage
docker system df -v

# Clean up unused resources
docker system prune -a -f

# Check LXC container storage
pct exec 154 -- df -h
```

### Diagnostic Commands

**Comprehensive system check:**
```bash
# Create diagnostic script
cat << 'EOF' > /opt/docker-diagnostics.sh
#!/bin/bash
echo "=== DOCKER DIAGNOSTICS $(date) ==="

echo "DOCKER VERSION:"
docker version

echo -e "\nDOCKER INFO:"
docker info | head -20

echo -e "\nRUNNING CONTAINERS:"
docker ps

echo -e "\nFAILED CONTAINERS:"
docker ps -a --filter "status=exited"

echo -e "\nSYSTEM USAGE:"
docker system df

echo -e "\nLXC CONTAINER DOCKER STATUS:"
for ct in 100 102 103 154; do
  echo "Container $ct:"
  if pct status $ct | grep -q running; then
    pct exec $ct -- docker ps 2>/dev/null | head -5 || echo "  Docker not accessible"
  else
    echo "  LXC container not running"
  fi
done
EOF

chmod +x /opt/docker-diagnostics.sh
```

---

## Advanced Operations

### Multi-Host Docker Management

**Coordinate operations across infrastructure:**
```bash
# Synchronized update across all Docker instances
claude mcp invoke proxmox-production execute_command \
  --command "echo 'Starting coordinated Docker update...' && docker pull proxmox-mcp-server:latest && for ct in 100 102 103 154; do echo 'Updating container $ct...'; pct exec $ct -- docker pull $(docker ps --format '{{.Image}}' | head -1) 2>/dev/null || echo 'No updates needed'; done && echo 'Update complete'"
```

### Docker Swarm Considerations

**Evaluate Swarm mode potential:**
```bash
# Check if Swarm mode is beneficial
docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')

# Consider LXC containers as Swarm nodes
# Note: This requires careful networking configuration
```

### Container Orchestration

**Docker Compose across infrastructure:**
```bash
# Centralized compose management
cat << 'EOF' > /opt/docker-compose-manager.sh
#!/bin/bash
# Manage Docker Compose across all containers

ACTION=${1:-status}
CONTAINERS="100 102 103 154"

case $ACTION in
  "up")
    echo "Starting all Docker Compose services..."
    docker-compose up -d
    for ct in $CONTAINERS; do
      echo "Starting services in Container $ct..."
      pct exec $ct -- docker-compose up -d 2>/dev/null || echo "No compose file in $ct"
    done
    ;;
  "down")
    echo "Stopping all Docker Compose services..."
    for ct in $CONTAINERS; do
      echo "Stopping services in Container $ct..."
      pct exec $ct -- docker-compose down 2>/dev/null || echo "No compose file in $ct"
    done
    docker-compose down
    ;;
  "status")
    echo "Docker Compose status across infrastructure:"
    docker-compose ps
    for ct in $CONTAINERS; do
      echo -e "\n=== Container $ct ==="
      pct exec $ct -- docker-compose ps 2>/dev/null || echo "No compose services"
    done
    ;;
esac
EOF

chmod +x /opt/docker-compose-manager.sh
```

### Automation and Scheduling

**Automated maintenance cron jobs:**
```bash
# Add to crontab
cat << 'EOF' > /etc/cron.d/docker-maintenance
# Docker maintenance tasks
0 2 * * 0 root /opt/scripts/docker-cleanup.sh >> /var/log/docker-cleanup.log 2>&1
0 6 * * * root /opt/scripts/docker-health-check.sh >> /var/log/docker-health.log 2>&1
0 4 * * 1 root /opt/docker-performance-report.sh >> /var/log/docker-performance.log 2>&1
EOF
```

---

## Integration with Proxmox MCP

### MCP-Enabled Docker Operations

**Use MCP tools for Docker management:**
```bash
# Check all Docker containers via MCP
claude mcp invoke proxmox-production execute_command \
  --command "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' && echo -e '\n=== LXC DOCKER CONTAINERS ===' && for ct in 100 102 103 154; do echo -e '\n--- Container $ct ---'; pct exec $ct -- docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || echo 'No Docker containers'; done"
```

**Automated reporting through MCP:**
```bash
# Generate comprehensive Docker report
claude mcp invoke proxmox-production execute_command \
  --command "/opt/docker-performance-report.sh && echo -e '\n=== DOCKER SECURITY STATUS ===' && docker info | grep -E '(Rootless|Security|Cgroup)' && echo -e '\n=== STORAGE USAGE ===' && docker system df"
```

### MCP Integration Best Practices

1. **Use MCP execute_command for Docker operations**
2. **Leverage Proxmox API for container lifecycle management**
3. **Combine Docker stats with VM/LXC monitoring**
4. **Automate routine tasks through MCP scripts**
5. **Maintain centralized logging and monitoring**

---

## Conclusion

This comprehensive Docker Administration Guide provides complete coverage of Docker management across the Proxmox infrastructure using MCP tools. The guide includes:

- **20+ Docker images** mapped across host and LXC containers
- **Practical administration examples** using real infrastructure
- **Security and compliance** procedures
- **Performance monitoring** and optimization
- **Integration patterns** with Proxmox and MCP
- **Troubleshooting procedures** for common issues
- **Advanced operations** for complex scenarios

The MCP system provides powerful capabilities for managing Docker across distributed infrastructure, enabling centralized control while maintaining the flexibility of containerized applications.

**Key Benefits:**
- Centralized Docker management across all infrastructure
- Real-time monitoring and diagnostics
- Automated maintenance and cleanup
- Security compliance and access control
- Performance optimization and resource management
- Disaster recovery and backup procedures

Use this guide as the definitive reference for Docker administration in your Proxmox MCP environment.