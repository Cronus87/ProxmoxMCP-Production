# Proxmox MCP - Administrator Guide

**Complete Operations and Maintenance Guide for Production Deployment**

## Overview

This guide provides comprehensive information for administrators managing the Proxmox MCP system in production environments. It covers daily operations, maintenance procedures, monitoring, troubleshooting, and advanced configuration.

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Daily Operations](#daily-operations)
3. [Service Management](#service-management)
4. [Monitoring and Alerting](#monitoring-and-alerting)
5. [Maintenance Procedures](#maintenance-procedures)
6. [Configuration Management](#configuration-management)
7. [Performance Optimization](#performance-optimization)
8. [Backup and Recovery](#backup-and-recovery)
9. [Security Administration](#security-administration)
10. [Upgrade Procedures](#upgrade-procedures)

---

## System Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                 PROXMOX MCP SYSTEM                      │
├─────────────────────────────────────────────────────────┤
│ External Access Layer                                   │
│   • Caddy Reverse Proxy (HTTPS/SSL termination)        │
│   • Rate limiting and DDoS protection                  │
├─────────────────────────────────────────────────────────┤
│ Application Layer                                       │
│   • MCP Server (FastAPI/HTTP)                          │
│   • SSH Client for Proxmox communication               │
│   • API clients for Proxmox management                 │
├─────────────────────────────────────────────────────────┤
│ Security Layer                                          │
│   • Bulletproof sudo configuration (85+ controls)      │
│   • SSH key authentication                              │
│   • Container security hardening                       │
├─────────────────────────────────────────────────────────┤
│ Infrastructure Layer                                    │
│   • Docker containerization                            │
│   • Systemd service management                         │
│   • Network isolation and monitoring                   │
├─────────────────────────────────────────────────────────┤
│ Monitoring Layer (Optional)                             │
│   • Prometheus metrics collection                      │
│   • Grafana visualization                              │
│   • Comprehensive logging                              │
└─────────────────────────────────────────────────────────┘
```

### File System Layout

```
/opt/proxmox-mcp/                    # Main installation directory
├── .env                             # Environment configuration
├── docker-compose.yml               # Container orchestration
├── keys/                            # SSH keys and certificates
│   ├── claude_proxmox_key           # Private SSH key
│   └── claude_proxmox_key.pub       # Public SSH key
├── config/                          # Application configuration
├── logs/                            # Application logs
├── caddy/                           # Reverse proxy configuration
│   └── Caddyfile                    # Caddy configuration
├── monitoring/                      # Monitoring configuration
│   ├── prometheus.yml               # Prometheus configuration
│   └── grafana/                     # Grafana dashboards
└── installation-report-*.md         # Installation documentation

/etc/sudoers.d/claude-user           # Security configuration
/var/log/sudo-claude-user.log        # Command audit log
/var/log/sudo-io/claude-user/        # I/O session logs
/etc/systemd/system/proxmox-mcp.service  # Systemd service
```

### Network Architecture

```
Internet/External Network
        ↓
    Firewall/Router
        ↓
┌───────────────────────┐
│    Proxmox Host       │
│  192.168.1.X:443/80  │ ←─── HTTPS/HTTP (Caddy)
│  192.168.1.X:8080    │ ←─── Direct MCP access
│  192.168.1.X:22      │ ←─── SSH management
│  192.168.1.X:3000    │ ←─── Grafana (optional)
│  192.168.1.X:9090    │ ←─── Prometheus (optional)
└───────────────────────┘
        ↓
┌───────────────────────┐
│   Docker Network     │
│   172.20.0.0/16      │
│ ┌─────────────────┐   │
│ │  MCP Container  │   │
│ │  172.20.0.2     │   │
│ └─────────────────┘   │
│ ┌─────────────────┐   │
│ │ Caddy Container │   │
│ │  172.20.0.3     │   │
│ └─────────────────┘   │
└───────────────────────┘
```

---

## Daily Operations

### Morning Health Check

**Complete System Status Check:**
```bash
#!/bin/bash
# /opt/proxmox-mcp/daily-health-check.sh

echo "=== PROXMOX MCP DAILY HEALTH CHECK ==="
echo "Date: $(date)"
echo ""

# 1. Service Status
echo "1. SERVICE STATUS:"
systemctl is-active proxmox-mcp && echo "✅ Service: Active" || echo "❌ Service: Failed"
systemctl is-enabled proxmox-mcp && echo "✅ Service: Enabled" || echo "❌ Service: Disabled"

# 2. Container Status
echo ""
echo "2. CONTAINER STATUS:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(proxmox-mcp|mcp-)"

# 3. Health Endpoints
echo ""
echo "3. HEALTH ENDPOINTS:"
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    echo "✅ MCP Health: OK"
else
    echo "❌ MCP Health: Failed"
fi

if curl -s http://localhost:80 | grep -q "Caddy" 2>/dev/null; then
    echo "✅ Reverse Proxy: OK"
else
    echo "❌ Reverse Proxy: Failed"
fi

# 4. Resource Usage
echo ""
echo "4. RESOURCE USAGE:"
echo "Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "Disk: $(df -h /opt/proxmox-mcp | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')"
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)% used"

# 5. Security Status
echo ""
echo "5. SECURITY STATUS:"
if visudo -c -f /etc/sudoers.d/claude-user >/dev/null 2>&1; then
    echo "✅ Sudoers: Valid"
else
    echo "❌ Sudoers: Invalid"
fi

if test -f /opt/proxmox-mcp/keys/claude_proxmox_key; then
    echo "✅ SSH Key: Present"
else
    echo "❌ SSH Key: Missing"
fi

# 6. Recent Issues
echo ""
echo "6. RECENT ISSUES (last 24h):"
blocked_count=$(grep "command not allowed" /var/log/sudo-claude-user.log 2>/dev/null | grep "$(date +%Y-%m-%d)" | wc -l)
echo "Blocked commands: $blocked_count"

auth_failures=$(grep "authentication failure" /var/log/auth.log 2>/dev/null | grep claude-user | grep "$(date +%Y-%m-%d)" | wc -l)
echo "Auth failures: $auth_failures"

echo ""
echo "=== HEALTH CHECK COMPLETE ==="
```

**Automated Daily Check Setup:**
```bash
# Install daily health check
sudo cp /opt/proxmox-mcp/daily-health-check.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/daily-health-check.sh

# Schedule daily execution
sudo crontab -e
# Add: 0 8 * * * /usr/local/bin/daily-health-check.sh | mail -s "Proxmox MCP Daily Health" admin@company.com
```

### Service Monitoring

**Real-time Monitoring Commands:**
```bash
# Service status monitoring
watch -n 5 'systemctl status proxmox-mcp'

# Container monitoring
watch -n 10 'docker stats proxmox-mcp-server mcp-reverse-proxy --no-stream'

# Log monitoring
sudo tail -f /var/log/sudo-claude-user.log

# Network monitoring
watch -n 5 'netstat -tuln | grep -E "(22|80|443|8080)"'

# Resource monitoring
htop
iotop
```

### Log Analysis

**Daily Log Review:**
```bash
# Check for security events
sudo grep -i "blocked\|denied\|failed" /var/log/sudo-claude-user.log | tail -20

# Check authentication events
sudo grep claude-user /var/log/auth.log | grep "$(date +%Y-%m-%d)"

# Check service logs
sudo journalctl -u proxmox-mcp --since today

# Check container logs
sudo docker logs proxmox-mcp-server --since 24h
sudo docker logs mcp-reverse-proxy --since 24h

# Generate daily log summary
sudo logwatch --range yesterday --service proxmox-mcp --detail Med
```

---

## Service Management

### Systemd Service Control

**Service Management Commands:**
```bash
# Start service
sudo systemctl start proxmox-mcp

# Stop service  
sudo systemctl stop proxmox-mcp

# Restart service
sudo systemctl restart proxmox-mcp

# Reload configuration
sudo systemctl reload proxmox-mcp

# Enable auto-start
sudo systemctl enable proxmox-mcp

# Disable auto-start
sudo systemctl disable proxmox-mcp

# Check service status
sudo systemctl status proxmox-mcp

# View service logs
sudo journalctl -u proxmox-mcp -f
```

### Container Management

**Docker Compose Operations:**
```bash
# Navigate to installation directory
cd /opt/proxmox-mcp

# Start all services
sudo docker-compose up -d

# Stop all services
sudo docker-compose down

# Restart specific service
sudo docker-compose restart mcp-server

# View service status
sudo docker-compose ps

# View logs
sudo docker-compose logs -f mcp-server
sudo docker-compose logs --tail 100 caddy

# Pull latest images
sudo docker-compose pull

# Build local images
sudo docker-compose build --no-cache
```

**Individual Container Management:**
```bash
# List containers
sudo docker ps -a

# Start container
sudo docker start proxmox-mcp-server

# Stop container
sudo docker stop proxmox-mcp-server

# Restart container
sudo docker restart proxmox-mcp-server

# Execute commands in container
sudo docker exec -it proxmox-mcp-server bash
sudo docker exec proxmox-mcp-server curl http://localhost:8080/health

# View container logs
sudo docker logs proxmox-mcp-server --tail 50 -f

# Inspect container configuration
sudo docker inspect proxmox-mcp-server
```

### Service Configuration Updates

**Environment Configuration:**
```bash
# Edit environment file
sudo nano /opt/proxmox-mcp/.env

# Validate configuration
sudo docker-compose config

# Apply changes
sudo docker-compose down
sudo docker-compose up -d

# Verify changes
curl http://localhost:8080/health
```

**Docker Compose Updates:**
```bash
# Edit docker-compose.yml
sudo nano /opt/proxmox-mcp/docker-compose.yml

# Validate syntax
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml config

# Apply changes
cd /opt/proxmox-mcp
sudo docker-compose down
sudo docker-compose up -d

# Verify deployment
sudo docker-compose ps
```

---

## Monitoring and Alerting

### Built-in Monitoring

**Health Endpoints:**
```bash
# MCP server health
curl http://localhost:8080/health

# API documentation
curl http://localhost:8080/docs

# Metrics (if enabled)
curl http://localhost:8080/metrics

# Reverse proxy status
curl http://localhost:80

# Container health
sudo docker inspect proxmox-mcp-server | jq '.[0].State.Health'
```

### Prometheus Monitoring (Optional)

**Enable Monitoring:**
```bash
# Enable monitoring profile
echo "ENABLE_MONITORING=y" | sudo tee -a /opt/proxmox-mcp/.env

# Start monitoring services
cd /opt/proxmox-mcp
sudo docker-compose --profile monitoring up -d

# Verify monitoring services
sudo docker-compose ps
curl http://localhost:9090/targets  # Prometheus
curl http://localhost:3000         # Grafana
```

**Prometheus Configuration:**
```yaml
# /opt/proxmox-mcp/monitoring/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'proxmox-mcp'
    static_configs:
      - targets: ['mcp-server:8080']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
    metrics_path: '/metrics'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['host.docker.internal:9100']
```

### Grafana Dashboards

**Access Grafana:**
- URL: `http://YOUR_PROXMOX_IP:3000`
- Username: `admin`
- Password: `admin` (change on first login)

**Key Metrics to Monitor:**
- **Service Availability**: Uptime and health check status
- **Response Times**: API endpoint performance
- **Resource Usage**: CPU, memory, disk utilization
- **Request Volume**: Number of MCP requests per minute
- **Error Rates**: Failed requests and authentication errors
- **Security Events**: Blocked commands and auth failures

### Log Aggregation

**Centralized Logging Setup:**
```bash
# Install log aggregation (optional)
sudo docker run -d --name=loki \
  -p 3100:3100 \
  -v /opt/proxmox-mcp/loki:/etc/loki \
  grafana/loki:latest

# Configure log forwarding
sudo tee /opt/proxmox-mcp/monitoring/loki-config.yml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks
EOF
```

### Alerting Setup

**Email Alerts:**
```bash
# Install mail utilities
sudo apt install -y mailutils

# Configure mail alerts
sudo tee /opt/proxmox-mcp/alert-check.sh << 'EOF'
#!/bin/bash
SERVICE_STATUS=$(systemctl is-active proxmox-mcp)
HEALTH_STATUS=$(curl -s http://localhost:8080/health | jq -r '.status' 2>/dev/null)

if [ "$SERVICE_STATUS" != "active" ] || [ "$HEALTH_STATUS" != "healthy" ]; then
    echo "ALERT: Proxmox MCP service issue detected at $(date)" | \
    mail -s "Proxmox MCP Alert" admin@company.com
fi
EOF

sudo chmod +x /opt/proxmox-mcp/alert-check.sh

# Schedule alert checks
sudo crontab -e
# Add: */5 * * * * /opt/proxmox-mcp/alert-check.sh
```

**Slack/Discord Webhooks:**
```bash
# Slack notification script
sudo tee /opt/proxmox-mcp/slack-alert.sh << 'EOF'
#!/bin/bash
WEBHOOK_URL="YOUR_SLACK_WEBHOOK_URL"
MESSAGE="$1"

curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"🚨 Proxmox MCP Alert: $MESSAGE\"}" \
    "$WEBHOOK_URL"
EOF

sudo chmod +x /opt/proxmox-mcp/slack-alert.sh
```

---

## Maintenance Procedures

### Weekly Maintenance

**Weekly Maintenance Checklist:**
```bash
#!/bin/bash
# /opt/proxmox-mcp/weekly-maintenance.sh

echo "=== WEEKLY MAINTENANCE REPORT ==="
echo "Date: $(date)"
echo ""

# 1. Security validation
echo "1. RUNNING SECURITY VALIDATION:"
sudo -u claude-user ./comprehensive-security-validation.sh --brief

# 2. System updates check
echo ""
echo "2. CHECKING FOR UPDATES:"
sudo apt list --upgradable 2>/dev/null | grep -v "WARNING" | wc -l | xargs echo "Available package updates:"

# 3. Container image updates
echo ""
echo "3. CHECKING CONTAINER UPDATES:"
cd /opt/proxmox-mcp
sudo docker-compose pull --quiet
echo "Container images updated"

# 4. Log rotation and cleanup
echo ""
echo "4. LOG MAINTENANCE:"
sudo logrotate -f /etc/logrotate.d/proxmox-mcp
echo "Logs rotated"

# 5. Backup verification
echo ""
echo "5. BACKUP VERIFICATION:"
latest_backup=$(ls -t /opt/proxmox-mcp-backups/*.tar.gz 2>/dev/null | head -1)
if [ -n "$latest_backup" ]; then
    echo "Latest backup: $(basename $latest_backup)"
    echo "Backup size: $(du -h $latest_backup | cut -f1)"
else
    echo "❌ No backups found"
fi

# 6. Performance metrics
echo ""
echo "6. PERFORMANCE METRICS:"
echo "Uptime: $(uptime -p)"
echo "Load average: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory usage: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "Disk usage: $(df -h /opt/proxmox-mcp | tail -1 | awk '{print $5}')"

echo ""
echo "=== MAINTENANCE COMPLETE ==="
```

### Monthly Maintenance

**Comprehensive Monthly Tasks:**
```bash
#!/bin/bash
# /opt/proxmox-mcp/monthly-maintenance.sh

echo "=== MONTHLY MAINTENANCE REPORT ==="
echo "Date: $(date)"
echo ""

# 1. Full security audit
echo "1. SECURITY AUDIT:"
sudo ./comprehensive-security-validation.sh > /tmp/security-audit.log
grep -E "(PASSED|FAILED)" /tmp/security-audit.log | tail -10

# 2. System updates
echo ""
echo "2. SYSTEM UPDATES:"
sudo apt update && sudo apt upgrade -y
echo "System updated"

# 3. Container updates
echo ""
echo "3. CONTAINER UPDATES:"
cd /opt/proxmox-mcp
sudo docker-compose pull
sudo docker-compose up -d
echo "Containers updated"

# 4. Certificate renewal (if using HTTPS)
echo ""
echo "4. CERTIFICATE STATUS:"
if sudo docker exec mcp-reverse-proxy caddy list-certificates 2>/dev/null; then
    echo "Certificates listed above"
else
    echo "No managed certificates"
fi

# 5. Configuration backup
echo ""
echo "5. CONFIGURATION BACKUP:"
backup_dir="/opt/proxmox-mcp-backups/monthly-$(date +%Y%m)"
sudo mkdir -p "$backup_dir"
sudo cp -r /opt/proxmox-mcp "$backup_dir/"
sudo cp /etc/sudoers.d/claude-user "$backup_dir/"
echo "Configuration backed up to $backup_dir"

# 6. Performance analysis
echo ""
echo "6. PERFORMANCE ANALYSIS:"
echo "Average response time (last 30 days):"
sudo grep "GET /health" /var/log/nginx/access.log 2>/dev/null | \
    awk '{print $10}' | sort -n | awk '{sum+=$1; count++} END {print sum/count "ms"}' || echo "No data available"

echo ""
echo "=== MONTHLY MAINTENANCE COMPLETE ==="
```

### Quarterly Maintenance

**Major Maintenance Tasks:**
```bash
# 1. API token rotation
echo "Rotating API tokens..."
# Create new token in Proxmox web interface
# Update configuration with new token
sudo nano /opt/proxmox-mcp/.env
sudo systemctl restart proxmox-mcp

# 2. SSH key rotation
echo "Rotating SSH keys..."
sudo ssh-keygen -t ed25519 -f /opt/proxmox-mcp/keys/claude_proxmox_key_new -C "quarterly-rotation-$(date +%Y%m%d)" -N ""
ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key_new.pub claude-user@YOUR_PROXMOX_IP
# Test new key before removing old one

# 3. Disaster recovery test
echo "Testing disaster recovery..."
sudo ./install.sh --test-recovery

# 4. Security assessment
echo "Running security assessment..."
sudo ./comprehensive-security-validation.sh --full-report > /tmp/quarterly-security-report.txt

# 5. Performance optimization
echo "Optimizing performance..."
sudo docker system prune -f
sudo apt autoremove -y
sudo apt autoclean
```

---

## Configuration Management

### Environment Configuration

**Configuration File Structure:**
```bash
# /opt/proxmox-mcp/.env
# Core configuration parameters

# Container Configuration
IMAGE_TAG=latest                     # Container image version
LOG_LEVEL=INFO                       # Logging verbosity (DEBUG, INFO, WARN, ERROR)

# SSH Configuration
SSH_TARGET=proxmox                   # SSH target type
SSH_HOST=192.168.1.137              # Proxmox server IP
SSH_USER=claude-user                 # SSH username
SSH_PORT=22                          # SSH port
SSH_KEY_PATH=/app/keys/claude_proxmox_key  # SSH private key path

# Proxmox API Configuration
PROXMOX_HOST=192.168.1.137          # Proxmox API host
PROXMOX_USER=root@pam               # Proxmox API user
PROXMOX_TOKEN_NAME=claude-mcp       # API token name
PROXMOX_TOKEN_VALUE=xxxxxxxx        # API token value
PROXMOX_VERIFY_SSL=false            # SSL verification

# Feature Configuration
ENABLE_PROXMOX_API=true             # Enable Proxmox API features
ENABLE_DANGEROUS_COMMANDS=false     # Allow dangerous commands
ENABLE_LOCAL_EXECUTION=false        # Enable local command execution
ENABLE_SSH=true                     # Enable SSH connectivity

# MCP Server Configuration
MCP_HOST=0.0.0.0                    # Bind address
MCP_PORT=8080                       # Listen port

# Monitoring Configuration
ENABLE_MONITORING=false             # Enable Prometheus/Grafana
GRAFANA_PASSWORD=admin              # Grafana admin password
```

**Configuration Validation:**
```bash
# Validate environment configuration
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml config

# Test configuration changes
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml up --dry-run

# Validate specific settings
source /opt/proxmox-mcp/.env && echo "SSH_HOST: $SSH_HOST, MCP_PORT: $MCP_PORT"
```

### Advanced Configuration

**Custom Port Configuration:**
```bash
# Change MCP port
sudo nano /opt/proxmox-mcp/.env
# Update MCP_PORT=9090

# Update Docker Compose port mapping
sudo nano /opt/proxmox-mcp/docker-compose.yml
# Change ports: "127.0.0.1:9090:9090"

# Update Claude Code configuration
nano ~/.claude.json
# Update URL to use new port

# Apply changes
cd /opt/proxmox-mcp
sudo docker-compose down
sudo docker-compose up -d
```

**External Access Configuration:**
```bash
# Enable external access
sudo nano /opt/proxmox-mcp/docker-compose.yml
# Change "127.0.0.1:8080:8080" to "8080:8080"

# Configure firewall
sudo ufw allow 8080/tcp

# Update reverse proxy
sudo nano /opt/proxmox-mcp/caddy/Caddyfile
# Add external domain configuration

# Restart services
sudo docker-compose restart
```

**SSL/TLS Configuration:**
```bash
# Configure custom domain
sudo nano /opt/proxmox-mcp/caddy/Caddyfile

your-domain.com {
    reverse_proxy mcp-server:8080
    tls your-email@domain.com
}

# DNS configuration required:
# your-domain.com A record -> YOUR_PROXMOX_IP

# Restart Caddy
sudo docker-compose restart caddy

# Update Claude Code configuration
nano ~/.claude.json
# Change URL to https://your-domain.com/api/mcp
```

---

## Performance Optimization

### Resource Optimization

**Container Resource Limits:**
```yaml
# Optimize docker-compose.yml
services:
  mcp-server:
    deploy:
      resources:
        limits:
          cpus: '1.0'          # Adjust based on load
          memory: 1G           # Adjust based on usage
        reservations:
          cpus: '0.25'
          memory: 256M
```

**System Performance Tuning:**
```bash
# Optimize system parameters
sudo tee -a /etc/sysctl.conf << 'EOF'
# Proxmox MCP optimizations
vm.swappiness=10
net.core.somaxconn=1024
net.core.netdev_max_backlog=5000
net.ipv4.tcp_max_syn_backlog=1024
EOF

sudo sysctl -p

# Optimize Docker daemon
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl restart docker
```

**Database Optimization (if applicable):**
```bash
# Optimize log storage
sudo logrotate -f /etc/logrotate.d/proxmox-mcp

# Clean old logs
sudo find /var/log -name "*.log.*" -mtime +30 -delete
sudo find /var/log/sudo-io -type f -mtime +30 -delete

# Optimize Docker storage
sudo docker system prune -f
sudo docker volume prune -f
```

### Performance Monitoring

**Performance Metrics Collection:**
```bash
# CPU and memory monitoring
while true; do
    echo "$(date): $(docker stats proxmox-mcp-server --no-stream --format 'CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}')"
    sleep 60
done > /var/log/proxmox-mcp-performance.log &

# Response time monitoring
while true; do
    response_time=$(curl -w "%{time_total}" -s -o /dev/null http://localhost:8080/health)
    echo "$(date): Health endpoint response time: ${response_time}s"
    sleep 300
done >> /var/log/proxmox-mcp-response-times.log &
```

**Performance Analysis:**
```bash
# Analyze response times
awk '{print $6}' /var/log/proxmox-mcp-response-times.log | \
sort -n | awk '{
    sum += $1
    values[NR] = $1
}
END {
    n = NR
    mean = sum / n
    if (n % 2 == 1) median = values[(n+1)/2]
    else median = (values[n/2] + values[n/2+1]) / 2
    print "Mean:", mean "s"
    print "Median:", median "s"
    print "Min:", values[1] "s"
    print "Max:", values[n] "s"
}'

# Resource usage trends
grep "Memory:" /var/log/proxmox-mcp-performance.log | \
tail -100 | awk -F'Memory: ' '{print $2}' | \
awk -F'/' '{print $1}' | sort -h
```

---

## Backup and Recovery

### Automated Backup System

**Daily Backup Script:**
```bash
#!/bin/bash
# /opt/proxmox-mcp/backup-daily.sh

BACKUP_ROOT="/opt/proxmox-mcp-backups"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/daily-$DATE"

echo "Starting daily backup: $DATE"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup configuration
cp -r /opt/proxmox-mcp "$BACKUP_DIR/"
cp -r /etc/sudoers.d/claude-user "$BACKUP_DIR/"

# Backup container volumes
docker run --rm -v mcp_logs:/data -v "$BACKUP_DIR":/backup \
  busybox tar czf /backup/mcp_logs.tar.gz -C /data .

docker run --rm -v caddy_data:/data -v "$BACKUP_DIR":/backup \
  busybox tar czf /backup/caddy_data.tar.gz -C /data .

# Create compressed archive
cd "$BACKUP_ROOT"
tar czf "daily-backup-$DATE.tar.gz" "daily-$DATE"
rm -rf "daily-$DATE"

# Cleanup old backups (keep 7 days)
find "$BACKUP_ROOT" -name "daily-backup-*.tar.gz" -mtime +7 -delete

echo "Daily backup completed: daily-backup-$DATE.tar.gz"
```

**Schedule Automated Backups:**
```bash
# Install backup script
sudo cp /opt/proxmox-mcp/backup-daily.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/backup-daily.sh

# Schedule daily backups
sudo crontab -e
# Add: 0 2 * * * /usr/local/bin/backup-daily.sh >> /var/log/proxmox-mcp-backup.log 2>&1

# Schedule weekly full backups
sudo crontab -e  
# Add: 0 1 * * 0 /opt/proxmox-mcp/backup-full.sh >> /var/log/proxmox-mcp-backup.log 2>&1
```

### Recovery Procedures

**Complete System Recovery:**
```bash
#!/bin/bash
# Complete system recovery from backup

BACKUP_FILE="$1"
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    exit 1
fi

echo "Starting system recovery from: $BACKUP_FILE"

# Stop services
sudo systemctl stop proxmox-mcp
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml down

# Backup current state
sudo mv /opt/proxmox-mcp /opt/proxmox-mcp.pre-recovery.$(date +%Y%m%d-%H%M%S)

# Extract backup
sudo tar xzf "$BACKUP_FILE" -C /opt/
sudo mv /opt/daily-* /opt/proxmox-mcp

# Restore sudoers
sudo cp /opt/proxmox-mcp/claude-user /etc/sudoers.d/

# Restore container volumes
sudo docker volume create mcp_logs
sudo docker run --rm -v mcp_logs:/data -v /opt/proxmox-mcp:/backup \
  busybox tar xzf /backup/mcp_logs.tar.gz -C /data

sudo docker volume create caddy_data
sudo docker run --rm -v caddy_data:/data -v /opt/proxmox-mcp:/backup \
  busybox tar xzf /backup/caddy_data.tar.gz -C /data

# Validate configuration
sudo visudo -c -f /etc/sudoers.d/claude-user
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml config

# Start services
sudo systemctl start proxmox-mcp

# Verify recovery
sleep 30
curl http://localhost:8080/health
sudo -u claude-user ./comprehensive-security-validation.sh --brief

echo "System recovery completed"
```

**Partial Recovery Procedures:**

**Configuration Only Recovery:**
```bash
# Restore configuration only
sudo cp backup/opt/proxmox-mcp/.env /opt/proxmox-mcp/
sudo cp backup/claude-user /etc/sudoers.d/
sudo systemctl restart proxmox-mcp
```

**SSH Key Recovery:**
```bash
# Restore SSH keys
sudo cp backup/opt/proxmox-mcp/keys/* /opt/proxmox-mcp/keys/
sudo chmod 600 /opt/proxmox-mcp/keys/claude_proxmox_key
sudo chmod 644 /opt/proxmox-mcp/keys/claude_proxmox_key.pub
```

**Security Configuration Recovery:**
```bash
# Restore security configuration
sudo cp backup/claude-user /etc/sudoers.d/
sudo visudo -c -f /etc/sudoers.d/claude-user
sudo ./deploy-enhanced-security.sh --verify
```

### Disaster Recovery Testing

**Monthly DR Test:**
```bash
#!/bin/bash
# Monthly disaster recovery test

echo "=== DISASTER RECOVERY TEST ==="
echo "Date: $(date)"

# Create test backup
./backup-daily.sh
latest_backup=$(ls -t /opt/proxmox-mcp-backups/daily-backup-*.tar.gz | head -1)

# Test backup integrity
if tar tzf "$latest_backup" >/dev/null 2>&1; then
    echo "✅ Backup integrity: OK"
else
    echo "❌ Backup integrity: FAILED"
    exit 1
fi

# Test configuration extraction
temp_dir="/tmp/dr-test-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$temp_dir"
tar xzf "$latest_backup" -C "$temp_dir"

# Validate extracted configuration
if docker-compose -f "$temp_dir"/*/docker-compose.yml config >/dev/null 2>&1; then
    echo "✅ Configuration validation: OK"
else
    echo "❌ Configuration validation: FAILED"
fi

# Cleanup test files
rm -rf "$temp_dir"

echo "✅ Disaster recovery test completed"
```

---

## Security Administration

### Security Monitoring

**Real-time Security Monitoring:**
```bash
# Monitor security events
sudo tail -f /var/log/sudo-claude-user.log | grep -E "(COMMAND|command not allowed)"

# Monitor authentication events
sudo tail -f /var/log/auth.log | grep claude-user

# Monitor failed SSH attempts
sudo tail -f /var/log/auth.log | grep "Failed password"

# Monitor container security
sudo docker events --filter container=proxmox-mcp-server
```

**Security Audit Dashboard:**
```bash
#!/bin/bash
# Security audit dashboard

echo "=== SECURITY AUDIT DASHBOARD ==="
echo "Generated: $(date)"
echo ""

# Recent security events
echo "RECENT SECURITY EVENTS (last 24h):"
echo "Blocked commands: $(grep 'command not allowed' /var/log/sudo-claude-user.log | grep "$(date +%Y-%m-%d)" | wc -l)"
echo "Auth failures: $(grep 'authentication failure' /var/log/auth.log | grep claude-user | grep "$(date +%Y-%m-%d)" | wc -l)"
echo "SSH attempts: $(grep 'Failed password' /var/log/auth.log | grep "$(date +%Y-%m-%d)" | wc -l)"

# Configuration status
echo ""
echo "CONFIGURATION STATUS:"
if visudo -c -f /etc/sudoers.d/claude-user >/dev/null 2>&1; then
    echo "✅ Sudoers configuration: Valid"
else
    echo "❌ Sudoers configuration: Invalid"
fi

if test -f /opt/proxmox-mcp/keys/claude_proxmox_key; then
    echo "✅ SSH key: Present"
    key_age=$(stat -c %Y /opt/proxmox-mcp/keys/claude_proxmox_key)
    current_time=$(date +%s)
    days_old=$(( (current_time - key_age) / 86400 ))
    echo "   Key age: $days_old days"
else
    echo "❌ SSH key: Missing"
fi

# Container security
echo ""
echo "CONTAINER SECURITY:"
if docker inspect proxmox-mcp-server | jq -e '.[0].HostConfig.SecurityOpt[]' | grep -q "no-new-privileges"; then
    echo "✅ No new privileges: Enabled"
else
    echo "❌ No new privileges: Disabled"
fi

if docker inspect proxmox-mcp-server | jq -e '.[0].HostConfig.ReadonlyRootfs' | grep -q "true"; then
    echo "✅ Read-only filesystem: Enabled"
else
    echo "❌ Read-only filesystem: Disabled"
fi

echo ""
echo "=== AUDIT COMPLETE ==="
```

### Access Management

**User Management:**
```bash
# Check user status
ssh root@YOUR_PROXMOX_IP "id claude-user"

# Check user groups
ssh root@YOUR_PROXMOX_IP "groups claude-user"

# Check SSH keys
ssh root@YOUR_PROXMOX_IP "cat /home/claude-user/.ssh/authorized_keys"

# Check sudo permissions
sudo -u claude-user sudo -l | head -20
```

**Permission Auditing:**
```bash
# Audit file permissions
ls -la /opt/proxmox-mcp/keys/
ls -la /etc/sudoers.d/
ls -la /var/log/sudo-claude-user.log

# Audit container permissions
docker inspect proxmox-mcp-server | jq '.[0].Config.User'
docker exec proxmox-mcp-server id

# Audit network permissions
sudo iptables -L INPUT | grep -E "(8080|80|443)"
sudo ufw status numbered
```

---

## Upgrade Procedures

### System Upgrades

**Operating System Updates:**
```bash
# Pre-upgrade backup
sudo /usr/local/bin/backup-daily.sh

# Check available updates
sudo apt list --upgradable

# Update package lists
sudo apt update

# Upgrade packages
sudo apt upgrade -y

# Reboot if required
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required after upgrade"
    sudo reboot
fi

# Post-upgrade verification
sudo systemctl status proxmox-mcp
curl http://localhost:8080/health
sudo -u claude-user ./comprehensive-security-validation.sh --brief
```

**Docker Upgrades:**
```bash
# Check Docker version
docker --version

# Update Docker (Ubuntu/Debian)
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Update Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify versions
docker --version
docker-compose --version

# Restart Docker
sudo systemctl restart docker
sudo systemctl restart proxmox-mcp
```

### Application Upgrades

**Container Image Updates:**
```bash
# Check current images
sudo docker images | grep proxmox-mcp

# Pull latest images
cd /opt/proxmox-mcp
sudo docker-compose pull

# Update containers with zero downtime
sudo docker-compose up -d

# Verify new versions
sudo docker images | grep proxmox-mcp
sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

# Test functionality
curl http://localhost:8080/health
sudo -u claude-user sudo /usr/sbin/qm list
```

**Configuration Schema Updates:**
```bash
# Backup current configuration
sudo cp /opt/proxmox-mcp/.env /opt/proxmox-mcp/.env.backup.$(date +%Y%m%d)

# Update configuration for new version
# (Follow specific upgrade notes for version)

# Validate new configuration
sudo docker-compose config

# Apply updates
sudo docker-compose down
sudo docker-compose up -d

# Verify functionality
curl http://localhost:8080/health
```

### Security Updates

**Security Configuration Updates:**
```bash
# Update security configuration
sudo ./deploy-enhanced-security.sh

# Run security validation
sudo -u claude-user ./comprehensive-security-validation.sh

# Check for security vulnerabilities
sudo docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image proxmox-mcp-server:latest

# Update security dependencies
cd /opt/proxmox-mcp
sudo docker-compose build --no-cache
sudo docker-compose up -d
```

### Rollback Procedures

**Application Rollback:**
```bash
# Identify previous image version
sudo docker images | grep proxmox-mcp

# Rollback to previous version
sudo nano /opt/proxmox-mcp/docker-compose.yml
# Change image tag to previous version

# Apply rollback
sudo docker-compose down
sudo docker-compose up -d

# Verify rollback
curl http://localhost:8080/health
sudo docker ps --format "table {{.Names}}\t{{.Image}}"
```

**Configuration Rollback:**
```bash
# Restore previous configuration
sudo cp /opt/proxmox-mcp/.env.backup.YYYYMMDD /opt/proxmox-mcp/.env

# Restart services
sudo systemctl restart proxmox-mcp

# Verify configuration
sudo docker-compose config
curl http://localhost:8080/health
```

**Complete System Rollback:**
```bash
# Use disaster recovery procedure
latest_backup=$(ls -t /opt/proxmox-mcp-backups/daily-backup-*.tar.gz | head -1)
sudo ./recovery-script.sh "$latest_backup"

# Verify system state
sudo systemctl status proxmox-mcp
curl http://localhost:8080/health
sudo -u claude-user ./comprehensive-security-validation.sh
```

---

## Emergency Procedures

### Service Recovery

**Quick Service Recovery:**
```bash
# Emergency restart
sudo systemctl restart proxmox-mcp

# Force container restart
sudo docker restart proxmox-mcp-server mcp-reverse-proxy

# Emergency rebuild
cd /opt/proxmox-mcp
sudo docker-compose down
sudo docker-compose build --no-cache
sudo docker-compose up -d
```

### Emergency Contacts

**Escalation Matrix:**
1. **Level 1**: System Administrator (daily operations)
2. **Level 2**: Security Team (security incidents)
3. **Level 3**: Infrastructure Team (hardware/network issues)
4. **Level 4**: Development Team (application issues)

**Contact Information:**
- System Admin: admin@company.com
- Security Team: security@company.com
- On-call: +1-XXX-XXX-XXXX

---

**Administrator Responsibilities:**

✅ **Daily**: Health checks, log monitoring, security review  
✅ **Weekly**: Maintenance tasks, security validation, updates  
✅ **Monthly**: Full audit, performance review, backup verification  
✅ **Quarterly**: Security assessment, disaster recovery testing  

The Proxmox MCP system is designed for enterprise operations with comprehensive monitoring, automated maintenance, and robust security controls.