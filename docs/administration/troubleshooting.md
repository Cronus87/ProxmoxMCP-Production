# Proxmox MCP - Troubleshooting Guide

**Comprehensive troubleshooting for production deployment with practical admin model**

## ✅ Recent Fixes Applied (install.sh v2.0)

**CRITICAL FIXES IMPLEMENTED:**

1. **✅ SSH Key Path Mismatch FIXED**
   - **Problem**: Container expected `/app/keys/ssh_key` but install.sh created different name
   - **Fix**: Generate SSH key as `$KEYS_DIR/ssh_key` with correct container ownership (1000:1000)
   - **Impact**: Container can now access SSH keys immediately after installation

2. **✅ MCP Endpoint Configuration FIXED**
   - **Problem**: Client instructions referenced wrong `/api` endpoint
   - **Fix**: All instructions now correctly use `/api/mcp` endpoint
   - **Impact**: MCP connection works immediately without manual corrections

3. **✅ End-to-End Validation ADDED**
   - **Problem**: Install.sh only tested health endpoint, not actual MCP tools
   - **Fix**: Added real execute_command testing during installation
   - **Impact**: Installation fails if MCP tools don't work, ensuring working deployment

4. **✅ Container Permission Issues FIXED**
   - **Problem**: SSH keys had wrong ownership for container user
   - **Fix**: Set keys to 1000:1000 (mcpuser) during key generation
   - **Impact**: Container can access SSH keys without permission errors

5. **✅ Practical Admin Model DEPLOYED**
   - **Problem**: Overly restrictive security prevented real admin work
   - **Fix**: Implement practical admin model - allow admin tools, block only catastrophic operations
   - **Impact**: Full VM/LXC/Docker management while maintaining security

6. **✅ Development Artifacts CLEANED**
   - **Problem**: Emergency troubleshooting files polluting production
   - **Fix**: Removed all emergency-*.py, fix-*.sh, restart-*.sh files
   - **Impact**: Clean production environment

## Table of Contents

1. [Installation Issues](#installation-issues)
2. [Service Issues](#service-issues)
3. [Authentication Issues](#authentication-issues)
4. [Network Issues](#network-issues)
5. [Security Issues](#security-issues)
6. [Claude Code Integration Issues](#claude-code-integration-issues)
7. [Performance Issues](#performance-issues)
8. [Monitoring Issues](#monitoring-issues)
9. [Diagnostic Tools](#diagnostic-tools)
10. [Emergency Procedures](#emergency-procedures)

---

## Installation Issues

### Issue: Prerequisites Installation Fails

**Symptoms:**
- Docker installation fails
- Package installation errors
- Permission denied errors

**Solutions:**

```bash
# Check OS compatibility
cat /etc/os-release
# Supported: Debian 11/12, Ubuntu 20.04/22.04

# Manual Docker installation
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Fix package manager issues
sudo apt clean
sudo apt update --fix-missing
sudo apt upgrade -y

# Check disk space
df -h
# Ensure at least 20GB free space
```

### Issue: SSH Key Access Issues

**Symptoms:**
- Container can't access SSH keys
- Permission denied from container
- SSH authentication fails from MCP tools

**Root Cause:** SSH key ownership must be 1000:1000 for container access

**Solutions:**

```bash
# Check current key ownership
ls -la /opt/proxmox-mcp/keys/

# Fix key ownership (CRITICAL for container access)
sudo chown -R 1000:1000 /opt/proxmox-mcp/keys/
sudo chmod 600 /opt/proxmox-mcp/keys/ssh_key
sudo chmod 644 /opt/proxmox-mcp/keys/ssh_key.pub

# Test container can access keys
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml exec mcp-server ls -la /app/keys/

# Test SSH connection from container
sudo docker-compose -f docker-compose.prod.yml exec mcp-server ssh -i /app/keys/ssh_key -o BatchMode=yes claude-user@localhost whoami

# If key doesn't exist, regenerate with correct ownership
sudo rm -f /opt/proxmox-mcp/keys/ssh_key*
sudo ssh-keygen -t rsa -b 4096 -f /opt/proxmox-mcp/keys/ssh_key -N "" -C "claude-user@proxmox-mcp"
sudo chown 1000:1000 /opt/proxmox-mcp/keys/ssh_key*

# Redeploy public key to claude-user
sudo cp /opt/proxmox-mcp/keys/ssh_key.pub /home/claude-user/.ssh/authorized_keys
sudo chown claude-user:claude-user /home/claude-user/.ssh/authorized_keys
sudo chmod 600 /home/claude-user/.ssh/authorized_keys
```

### Issue: User Creation Fails

**Symptoms:**
- claude-user account creation fails
- User already exists errors
- Permission issues

**Solutions:**

```bash
# Check if user exists
ssh root@YOUR_PROXMOX_IP "id claude-user"

# Create user manually
ssh root@YOUR_PROXMOX_IP "useradd -m -s /bin/bash claude-user"
ssh root@YOUR_PROXMOX_IP "usermod -aG docker claude-user"

# Set up SSH directory
ssh root@YOUR_PROXMOX_IP "mkdir -p /home/claude-user/.ssh"
ssh root@YOUR_PROXMOX_IP "chmod 700 /home/claude-user/.ssh"
ssh root@YOUR_PROXMOX_IP "chown claude-user:claude-user /home/claude-user/.ssh"

# Delete and recreate if needed
ssh root@YOUR_PROXMOX_IP "userdel -r claude-user"
ssh root@YOUR_PROXMOX_IP "useradd -m -s /bin/bash claude-user"
```

### Issue: Configuration File Creation Fails

**Symptoms:**
- .env file creation errors
- Configuration validation fails
- Template file missing

**Solutions:**

```bash
# Manual configuration creation
sudo tee /opt/proxmox-mcp/.env << 'EOF'
# Proxmox MCP Configuration
IMAGE_TAG=latest
LOG_LEVEL=INFO

# SSH Configuration
SSH_TARGET=proxmox
SSH_HOST=YOUR_PROXMOX_IP
SSH_USER=claude-user
SSH_PORT=22
SSH_KEY_PATH=/app/keys/claude_proxmox_key

# Proxmox API Configuration
PROXMOX_HOST=YOUR_PROXMOX_IP
PROXMOX_USER=root@pam
PROXMOX_TOKEN_NAME=claude-mcp
PROXMOX_TOKEN_VALUE=YOUR_TOKEN_HERE
PROXMOX_VERIFY_SSL=false

# Feature Configuration
ENABLE_PROXMOX_API=true
ENABLE_DANGEROUS_COMMANDS=false

# MCP Server Configuration
MCP_HOST=0.0.0.0
MCP_PORT=8080
EOF

sudo chmod 640 /opt/proxmox-mcp/.env

# Validate configuration
sudo cat /opt/proxmox-mcp/.env
```

---

## Service Issues

### Issue: Container Fails to Start

**Symptoms:**
- Docker container won't start
- Container exits immediately
- Health check fails

**Diagnosis (Note Correct Paths):**

```bash
# Check container status (use correct docker-compose file)
cd /opt/proxmox-mcp/docker
sudo docker ps -a
sudo docker-compose -f docker-compose.prod.yml ps

# Check container logs
sudo docker logs proxmox-mcp-server
sudo docker-compose -f docker-compose.prod.yml logs mcp-server

# Check if container can access SSH keys
sudo docker-compose -f docker-compose.prod.yml exec mcp-server ls -la /app/keys/

# Check image availability
sudo docker images | grep proxmox-mcp
```

**Solutions:**

```bash
# Rebuild container (use correct compose file)
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml down
sudo docker-compose -f docker-compose.prod.yml build --no-cache
sudo docker-compose -f docker-compose.prod.yml up -d

# Fix SSH key permissions for container (most common issue)
sudo chown -R 1000:1000 /opt/proxmox-mcp/keys/
sudo chmod 600 /opt/proxmox-mcp/keys/ssh_key
sudo chmod 644 /opt/proxmox-mcp/keys/ssh_key.pub

# Check for port conflicts
sudo netstat -tlnp | grep 8080
sudo lsof -i :8080

# Restart services via systemd
sudo systemctl restart proxmox-mcp

# Manual container restart
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml restart mcp-server
```

### Issue: Systemd Service Fails

**Symptoms:**
- systemctl status shows failed
- Service won't start on boot
- Service restart fails

**Diagnosis:**

```bash
# Check service status
sudo systemctl status proxmox-mcp
sudo journalctl -u proxmox-mcp -f

# Check service file
sudo cat /etc/systemd/system/proxmox-mcp.service
```

**Solutions:**

```bash
# Recreate service file
sudo tee /etc/systemd/system/proxmox-mcp.service << 'EOF'
[Unit]
Description=Proxmox MCP HTTP Server
After=docker.service network.target
Requires=docker.service

[Service]
Type=forking
WorkingDirectory=/opt/proxmox-mcp
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
ExecReload=/usr/local/bin/docker-compose restart
RemainAfterExit=yes
Restart=on-failure
RestartSec=30
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl enable proxmox-mcp
sudo systemctl restart proxmox-mcp
```

### Issue: MCP Endpoint Access Fails

**Symptoms:**
- curl http://localhost:8080/health works but MCP tools don't
- Claude Code shows "connection failed" for MCP tools
- Wrong endpoint errors in Claude Code

**Root Cause:** MCP endpoint is `/api/mcp`, not just `/api`

**Diagnosis:**

```bash
# Test health endpoint (should work)
curl http://localhost:8080/health

# Test MCP endpoint specifically (most important)
curl http://localhost:8080/api/mcp

# Test MCP tools list
curl -X POST http://localhost:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'

# Check container internal access
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml exec mcp-server curl http://localhost:8080/api/mcp
```

**Solutions:**

```bash
# Restart services if MCP endpoint not responding
sudo systemctl restart proxmox-mcp

# Check container internal networking
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml exec mcp-server netstat -tlnp

# Rebuild container if application issues
sudo docker-compose -f docker-compose.prod.yml down
sudo docker-compose -f docker-compose.prod.yml build --no-cache
sudo docker-compose -f docker-compose.prod.yml up -d

# Fix Claude Code configuration (use correct endpoint)
claude mcp remove proxmox-production
claude mcp add --transport http proxmox-production http://YOUR_IP:8080/api/mcp
claude mcp list  # Should show proxmox-production

# Test in Claude Code
claude
# Try: "Please execute the command 'whoami'"
```

---

## Authentication Issues

### Issue: SSH Authentication Fails

**Symptoms:**
- SSH connection refused
- Permission denied (publickey)
- SSH key not accepted

**Diagnosis:**

```bash
# Test SSH connection with verbose output
ssh -v -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@YOUR_PROXMOX_IP

# Check key permissions
ls -la /opt/proxmox-mcp/keys/
stat /opt/proxmox-mcp/keys/claude_proxmox_key

# Check authorized_keys on server
ssh root@YOUR_PROXMOX_IP "ls -la /home/claude-user/.ssh/"
ssh root@YOUR_PROXMOX_IP "cat /home/claude-user/.ssh/authorized_keys"
```

**Solutions:**

```bash
# Fix key permissions
sudo chmod 600 /opt/proxmox-mcp/keys/claude_proxmox_key
sudo chmod 644 /opt/proxmox-mcp/keys/claude_proxmox_key.pub

# Re-deploy public key
ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key.pub claude-user@YOUR_PROXMOX_IP

# Check SSH daemon configuration
ssh root@YOUR_PROXMOX_IP "grep -E '^(PubkeyAuthentication|AuthorizedKeysFile)' /etc/ssh/sshd_config"

# Fix authorized_keys permissions on server
ssh root@YOUR_PROXMOX_IP "chmod 700 /home/claude-user/.ssh"
ssh root@YOUR_PROXMOX_IP "chmod 600 /home/claude-user/.ssh/authorized_keys"
ssh root@YOUR_PROXMOX_IP "chown -R claude-user:claude-user /home/claude-user/.ssh"
```

### Issue: Proxmox API Authentication Fails

**Symptoms:**
- API calls return authentication errors
- Token not recognized
- Permission denied errors

**Diagnosis:**

```bash
# Test API token manually
curl -k -H "Authorization: PVEAPIToken=root@pam!claude-mcp=YOUR_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version

# Check token in Proxmox logs
ssh root@YOUR_PROXMOX_IP "tail -f /var/log/pveproxy/access.log"
```

**Solutions:**

```bash
# Recreate API token in Proxmox web interface:
# 1. Go to Datacenter → Permissions → API Tokens
# 2. Delete existing token
# 3. Create new token with same name
# 4. Ensure "Privilege Separation" is UNCHECKED
# 5. Copy new token value

# Update configuration
sudo nano /opt/proxmox-mcp/.env
# Update PROXMOX_TOKEN_VALUE=NEW_TOKEN_HERE

# Restart service
sudo systemctl restart proxmox-mcp

# Test API access
curl -k -H "Authorization: PVEAPIToken=root@pam!claude-mcp=NEW_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version
```

### Issue: Practical Admin Permissions Problems

**Symptoms:**
- Normal admin commands being blocked
- "Command not allowed" errors for standard operations
- VM/LXC operations failing

**Root Cause:** Practical admin model may not be deployed correctly

**Diagnosis:**

```bash
# Check if practical admin configuration is deployed
sudo cat /etc/sudoers.d/claude-user | head -10
# Should show "Practical Admin Sudoers Configuration"

# Test basic admin operations (these should work)
sudo -u claude-user sudo systemctl status pveproxy
sudo -u claude-user sudo qm list
sudo -u claude-user sudo pct list
sudo -u claude-user sudo docker ps

# Test blocked operations (these should fail)
sudo -u claude-user sudo userdel root  # Should be blocked
sudo -u claude-user sudo systemctl stop pvedaemon  # Should be blocked

# Check sudoers syntax
sudo visudo -c -f /etc/sudoers.d/claude-user
```

**Solutions:**

```bash
# Redeploy practical admin configuration
cd /opt/proxmox-mcp
sudo ./scripts/install/install.sh  # Will update sudoers if needed

# Or manually deploy practical admin sudoers
sudo tee /etc/sudoers.d/claude-user << 'EOF'
# Proxmox MCP - Practical Admin Sudoers Configuration
# Philosophy: Enable real admin work, block only catastrophic actions

# User specification for claude-user
Defaults:claude-user !requiretty

# Core System Administration - Full access to standard admin tools
claude-user ALL=(ALL:ALL) NOPASSWD: /usr/bin/*, /usr/sbin/*, /bin/*, /sbin/*

# CATASTROPHIC OPERATION BLOCKS - These commands are explicitly forbidden
claude-user ALL=(ALL:ALL) !/usr/bin/pvecm delnode*, !/usr/sbin/pvecm delnode*
claude-user ALL=(ALL:ALL) !/usr/sbin/userdel root, !/usr/bin/userdel root
claude-user ALL=(ALL:ALL) !/usr/sbin/usermod root*, !/usr/bin/usermod root*
claude-user ALL=(ALL:ALL) !/usr/bin/pveum user delete root@pam*, !/usr/sbin/pveum user delete root@pam*
claude-user ALL=(ALL:ALL) !/usr/bin/pvesm remove *, !/usr/sbin/pvesm remove *
EOF

sudo chmod 440 /etc/sudoers.d/claude-user
sudo visudo -c -f /etc/sudoers.d/claude-user

# Test practical admin capabilities
sudo -u claude-user sudo qm list
sudo -u claude-user sudo systemctl status pveproxy
```

---

## Network Issues

### Issue: External Access Not Working

**Symptoms:**
- Cannot access from other machines
- Connection timeout from external hosts
- Internal access works, external fails

**Diagnosis:**

```bash
# Check listening ports
sudo netstat -tlnp | grep -E "(80|443|8080)"

# Check firewall rules
sudo ufw status numbered
sudo iptables -L -n

# Test from external host
curl -v http://YOUR_PROXMOX_IP:8080/health
```

**Solutions:**

```bash
# Open firewall ports
sudo ufw allow 8080/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check Docker port binding
sudo docker port proxmox-mcp-server

# Verify container configuration
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml config

# Fix port binding in docker-compose.yml
sudo nano /opt/proxmox-mcp/docker-compose.yml
# Change "127.0.0.1:8080:8080" to "8080:8080" for external access
```

### Issue: Reverse Proxy Problems

**Symptoms:**
- HTTPS not working
- SSL certificate errors
- Caddy proxy failures

**Diagnosis:**

```bash
# Check Caddy container
sudo docker logs mcp-reverse-proxy

# Check Caddy configuration
sudo cat /opt/proxmox-mcp/caddy/Caddyfile

# Test direct MCP access
curl http://localhost:8080/health
```

**Solutions:**

```bash
# Restart Caddy
sudo docker restart mcp-reverse-proxy

# Check Caddy config syntax
sudo docker exec mcp-reverse-proxy caddy validate --config /etc/caddy/Caddyfile

# Fix SSL issues (for custom domains)
sudo docker exec mcp-reverse-proxy caddy reload --config /etc/caddy/Caddyfile

# Manual certificate generation
sudo docker exec mcp-reverse-proxy caddy trust
```

### Issue: DNS Resolution Problems

**Symptoms:**
- Cannot resolve Proxmox hostname
- API calls to hostname fail
- Network timeouts

**Solutions:**

```bash
# Use IP addresses instead of hostnames
sudo nano /opt/proxmox-mcp/.env
# Change SSH_HOST and PROXMOX_HOST to IP addresses

# Add hosts entry
echo "YOUR_PROXMOX_IP proxmox.local" | sudo tee -a /etc/hosts

# Test DNS resolution
nslookup YOUR_PROXMOX_HOSTNAME
dig YOUR_PROXMOX_HOSTNAME
```

---

## Security Issues

### Issue: Security Validation Fails

**Symptoms:**
- Security test suite fails
- Commands blocked that should work
- Excessive permission errors

**Diagnosis:**

```bash
# Run security validation with verbose output
sudo -u claude-user ./comprehensive-security-validation.sh -v

# Check sudoers syntax
sudo visudo -c

# Review blocked commands
sudo grep "command not allowed" /var/log/sudo-claude-user.log
```

**Solutions:**

```bash
# Redeploy security configuration
sudo ./deploy-enhanced-security.sh

# Fix specific sudoers issues
sudo visudo -f /etc/sudoers.d/claude-user

# Reset security configuration
sudo rm /etc/sudoers.d/claude-user
sudo ./deploy-enhanced-security.sh

# Check for conflicting sudoers rules
sudo grep -r claude-user /etc/sudoers.d/
```

### Issue: Command Execution Blocked

**Symptoms:**
- Legitimate commands being blocked
- "Command not allowed" errors
- Operations failing unexpectedly

**Diagnosis:**

```bash
# Check what's being blocked
sudo tail -f /var/log/sudo-claude-user.log

# Test specific command
sudo -u claude-user sudo /usr/sbin/qm list

# Check allowed commands
sudo -u claude-user sudo -l | head -20
```

**Solutions:**

```bash
# Allow specific command temporarily
echo "claude-user ALL=(ALL) NOPASSWD: /usr/sbin/specific-command" | sudo tee /etc/sudoers.d/temp-allow

# Update security configuration
sudo nano claude-user-security-enhanced-sudoers
# Add required command pattern

# Redeploy configuration
sudo ./deploy-enhanced-security.sh

# Remove temporary permission
sudo rm /etc/sudoers.d/temp-allow
```

### Issue: Log File Permissions

**Symptoms:**
- Cannot write to log files
- Log rotation issues
- Permission denied on log access

**Solutions:**

```bash
# Fix log permissions
sudo mkdir -p /var/log/sudo-io/claude-user
sudo chown claude-user:claude-user /var/log/sudo-io/claude-user
sudo chmod 750 /var/log/sudo-io/claude-user

# Fix main log file
sudo touch /var/log/sudo-claude-user.log
sudo chmod 640 /var/log/sudo-claude-user.log

# Set up log rotation
sudo tee /etc/logrotate.d/proxmox-mcp << 'EOF'
/var/log/sudo-claude-user.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF
```

---

## Claude Code Integration Issues

### Issue: MCP Tools Not Available in Claude Code

**Symptoms:**
- No MCP tools visible in Claude Code
- mcp__proxmox-production__ prefix missing
- Tools list empty or connection errors

**Root Cause:** Usually wrong endpoint URL or configuration

**Diagnosis:**

```bash
# Test MCP endpoint (use correct /api/mcp path)
curl -X POST http://YOUR_PROXMOX_IP:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'

# Should return tools list with execute_command, list_vms, vm_status, etc.

# Check Claude CLI configuration
claude mcp list
# Should show proxmox-production if configured correctly

# Test connectivity from Claude Code
claude
# In Claude: "Are MCP tools available?"
```

**Solutions:**

```bash
# Use Claude CLI (recommended approach)
claude mcp remove proxmox-production  # Remove if exists
claude mcp add --transport http proxmox-production http://YOUR_PROXMOX_IP:8080/api/mcp
claude mcp list  # Verify shows proxmox-production

# Test MCP tools in Claude Code
claude
# Try these commands:
# "Please execute the command 'whoami'"
# "Please list all VMs on the Proxmox server"
# "Please check the status of the pveproxy service"

# Alternative: Manual configuration
tee ~/.claude.json << 'EOF'
{
  "mcpServers": {
    "proxmox-production": {
      "command": "npx",
      "args": [
        "@modelcontextprotocol/server-fetch",
        "http://YOUR_PROXMOX_IP:8080/api/mcp"
      ],
      "transport": "stdio"
    }
  }
}
EOF
```

### Issue: MCP Tools Execute But Return Errors

**Symptoms:**
- Tools are available in Claude Code
- Commands execute but return permission errors
- SSH authentication failures in tool responses

**Root Cause:** Usually SSH key permissions or practical admin configuration

**Solutions:**

```bash
# Fix SSH key permissions (most common issue)
sudo chown -R 1000:1000 /opt/proxmox-mcp/keys/
sudo chmod 600 /opt/proxmox-mcp/keys/ssh_key

# Test SSH connectivity from container
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml exec mcp-server ssh -i /app/keys/ssh_key -o BatchMode=yes claude-user@localhost whoami

# Test practical admin permissions
sudo -u claude-user sudo qm list
sudo -u claude-user sudo systemctl status pveproxy

# Restart MCP service after fixes
sudo systemctl restart proxmox-mcp

# Test in Claude Code
claude
# "Please execute the command 'qm list' to show all VMs"
```

### Issue: MCP Connection Timeout

**Symptoms:**
- Tools available but timeout on execution
- Connection refused errors
- Slow response times

**Solutions:**

```bash
# Check network latency
ping YOUR_PROXMOX_IP

# Test HTTP response time
time curl http://YOUR_PROXMOX_IP:8080/health

# Increase timeout in Claude Code configuration
tee ~/.claude.json << 'EOF'
{
  "mcpServers": {
    "proxmox-production": {
      "type": "http",
      "url": "http://YOUR_PROXMOX_IP:8080/api/mcp",
      "timeout": 60000,
      "headers": {
        "Content-Type": "application/json"
      }
    }
  }
}
EOF
```

### Issue: Tool Execution Errors

**Symptoms:**
- Tools available but return errors
- Authentication failures in tool calls
- Partial functionality

**Diagnosis:**

```bash
# Test individual tools
curl -X POST http://YOUR_PROXMOX_IP:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_vms","arguments":{}},"id":"test"}'

# Check container logs for tool errors
sudo docker logs proxmox-mcp-server | grep -i error
```

**Solutions:**

```bash
# Restart MCP service
sudo systemctl restart proxmox-mcp

# Check authentication configuration
sudo cat /opt/proxmox-mcp/.env | grep -E "(SSH_|PROXMOX_)"

# Test SSH and API connectivity
ssh -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@YOUR_PROXMOX_IP "whoami"
curl -k -H "Authorization: PVEAPIToken=root@pam!claude-mcp=YOUR_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version
```

---

## Performance Issues

### Issue: Slow Response Times

**Symptoms:**
- MCP tools respond slowly
- High CPU/memory usage
- Container performance issues

**Diagnosis:**

```bash
# Check system resources
top
htop
free -h
df -h

# Check container resources
sudo docker stats proxmox-mcp-server

# Check network performance
ping YOUR_PROXMOX_IP
iperf3 -c YOUR_PROXMOX_IP # if iperf3 is available
```

**Solutions:**

```bash
# Increase container resources
sudo nano /opt/proxmox-mcp/docker-compose.yml
# Modify deploy.resources.limits and reservations

# Restart with new limits
sudo docker-compose down
sudo docker-compose up -d

# Optimize system performance
sudo apt install -y htop iotop
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
```

### Issue: Memory Issues

**Symptoms:**
- Out of memory errors
- Container killed by OOM killer
- System becomes unresponsive

**Solutions:**

```bash
# Check memory usage
free -h
sudo dmesg | grep -i "killed process"

# Increase swap space
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Reduce container memory usage
sudo nano /opt/proxmox-mcp/docker-compose.yml
# Reduce memory limits if too high
```

---

## Monitoring Issues

### Issue: Grafana Not Accessible

**Symptoms:**
- Cannot access Grafana dashboard
- Connection refused on port 3000
- Login issues

**Solutions:**

```bash
# Check if monitoring is enabled
grep ENABLE_MONITORING /opt/proxmox-mcp/.env

# Enable monitoring
echo "ENABLE_MONITORING=y" | sudo tee -a /opt/proxmox-mcp/.env

# Start monitoring services
sudo docker-compose --profile monitoring up -d

# Check Grafana logs
sudo docker logs mcp-grafana

# Access Grafana
# URL: http://YOUR_PROXMOX_IP:3000
# Username: admin
# Password: admin (or from GRAFANA_PASSWORD in .env)
```

### Issue: Prometheus Not Collecting Metrics

**Symptoms:**
- Empty dashboards
- No metrics in Prometheus
- Scrape failures

**Solutions:**

```bash
# Check Prometheus configuration
sudo cat /opt/proxmox-mcp/monitoring/prometheus.yml

# Check Prometheus targets
curl http://YOUR_PROXMOX_IP:9090/api/v1/targets

# Restart Prometheus
sudo docker restart mcp-prometheus

# Check if MCP server exposes metrics
curl http://YOUR_PROXMOX_IP:8080/metrics
```

---

## Diagnostic Tools

### Log Analysis Commands

```bash
# Service logs
sudo journalctl -u proxmox-mcp -f
sudo journalctl -u proxmox-mcp --since "1 hour ago"

# Container logs
sudo docker logs proxmox-mcp-server --tail 100 -f
sudo docker logs mcp-reverse-proxy --tail 50

# Security logs
sudo tail -f /var/log/sudo-claude-user.log
sudo tail -f /var/log/auth.log | grep claude-user

# Installation logs
sudo tail -f /var/log/proxmox-mcp-install.log

# System logs
sudo dmesg | tail -20
sudo tail -f /var/log/syslog | grep -i proxmox
```

### Network Diagnostic Commands

```bash
# Port scanning
nmap -p 22,80,443,8080 YOUR_PROXMOX_IP

# Connection testing
nc -zv YOUR_PROXMOX_IP 8080
telnet YOUR_PROXMOX_IP 8080

# Network interface status
ip addr show
ip route show

# DNS resolution
nslookup YOUR_PROXMOX_IP
dig YOUR_PROXMOX_IP
```

### System Health Commands

```bash
# Resource usage
htop
iotop
nethogs

# Disk usage
df -h
du -sh /opt/proxmox-mcp/*
sudo ncdu /opt/proxmox-mcp

# Service status
sudo systemctl status proxmox-mcp
sudo systemctl status docker
sudo docker ps -a

# Container health
sudo docker inspect proxmox-mcp-server | jq '.[0].State'
```

### Security Diagnostic Commands

```bash
# Check sudoers configuration
sudo visudo -c
sudo cat /etc/sudoers.d/claude-user

# Test security controls
sudo -u claude-user ./comprehensive-security-validation.sh

# Check file permissions
ls -la /opt/proxmox-mcp/keys/
ls -la /etc/sudoers.d/

# Audit logs
sudo ausearch -u claude-user
sudo grep claude-user /var/log/auth.log
```

---

## Emergency Procedures

### Emergency Service Restart

```bash
# Complete service restart
sudo systemctl stop proxmox-mcp
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml down
sudo systemctl start docker
sudo systemctl start proxmox-mcp

# Or force restart
sudo systemctl restart proxmox-mcp
```

### Emergency Configuration Reset

```bash
# Backup current configuration
sudo cp /opt/proxmox-mcp/.env /opt/proxmox-mcp/.env.backup.$(date +%Y%m%d-%H%M%S)

# Reset to default configuration
sudo ./install.sh --reset-config

# Or manual reset
sudo rm /opt/proxmox-mcp/.env
sudo cp .env.example /opt/proxmox-mcp/.env
sudo nano /opt/proxmox-mcp/.env  # Update with your settings
```

### Emergency Security Rollback

```bash
# Backup current sudoers
sudo cp /etc/sudoers.d/claude-user /etc/sudoers.d/claude-user.backup.$(date +%Y%m%d-%H%M%S)

# Restore basic sudoers
sudo tee /etc/sudoers.d/claude-user << 'EOF'
# Basic Proxmox MCP configuration for claude-user
claude-user ALL=(ALL) NOPASSWD: /usr/sbin/qm *, /usr/sbin/pct *, /usr/sbin/pvesm *, /usr/sbin/pvesh *, /usr/bin/systemctl status *
EOF

# Validate and restart
sudo visudo -c
sudo systemctl restart proxmox-mcp
```

### Emergency Access (Use with Extreme Caution)

```bash
# Temporary full access (DANGEROUS - USE ONLY IN EMERGENCIES)
echo "claude-user ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/emergency-access

# IMMEDIATELY REMOVE AFTER USE
sudo rm /etc/sudoers.d/emergency-access

# Restore proper security
sudo ./deploy-enhanced-security.sh
```

### Complete System Rollback

```bash
# Stop all services (note correct paths)
sudo systemctl stop proxmox-mcp
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml down

# Remove installation
sudo systemctl disable proxmox-mcp
sudo rm /etc/systemd/system/proxmox-mcp.service
sudo rm /etc/sudoers.d/claude-user
sudo rm -rf /opt/proxmox-mcp

# Remove user (optional)
sudo userdel -r claude-user

# Clean up Docker
sudo docker system prune -a
sudo docker volume prune

# Remove Claude Code configuration
claude mcp remove proxmox-production
```

---

## Getting Additional Help

### Support Resources

- **Installation Report**: `/opt/proxmox-mcp/installation-report-[ID].md`
- **Security Analysis**: `COMPREHENSIVE-SECURITY-ANALYSIS.md`
- **Full Documentation**: `docs/` directory

### Diagnostic Information to Collect

When seeking help, collect this information:

```bash
# System information
cat /etc/os-release
uname -a
docker --version
sudo systemctl --version

# Service status
sudo systemctl status proxmox-mcp
sudo docker ps -a
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml ps

# Configuration (redact sensitive values)
sudo cat /opt/proxmox-mcp/.env | sed 's/TOKEN_VALUE=.*/TOKEN_VALUE=REDACTED/'
cat ~/.claude.json

# Recent logs
sudo journalctl -u proxmox-mcp --since "1 hour ago" --no-pager
sudo docker logs proxmox-mcp-server --tail 50
```

## Practical Admin Model Troubleshooting

### What Should Work with Practical Admin Model

**VM and LXC Management:**
```bash
# These should work through Claude Code:
"Please list all VMs: qm list"
"Please show LXC containers: pct list"
"Please start VM 100: qm start 100"
"Please create a snapshot of VM 100: qm snapshot 100 snapshot-name"
"Please clone VM 100 to 110: qm clone 100 110"
"Please enter LXC container 100: pct exec 100 bash"
```

**Docker Operations:**
```bash
# These should work through Claude Code:
"Please show Docker containers: docker ps -a"
"Please show Docker images: docker images"
"Please start container nginx: docker start nginx"
"Please check container logs: docker logs container-name"
"Please execute command in container: docker exec container-name ls -la"
```

**System Administration:**
```bash
# These should work through Claude Code:
"Please check service status: systemctl status pveproxy"
"Please restart a service: systemctl restart networking"
"Please check disk usage: df -h"
"Please check running processes: ps aux"
"Please check network configuration: ip addr show"
```

**What Should Be Blocked (Catastrophic Operations):**
```bash
# These should fail (blocked by practical admin model):
"Please delete root user: userdel root"  # BLOCKED
"Please stop core PVE service: systemctl stop pvedaemon"  # BLOCKED
"Please delete cluster node: pvecm delnode node1"  # BLOCKED
"Please remove storage: pvesm remove storage1"  # BLOCKED
```

### System Recovery Procedures

#### Container Restart (Most Common Solution)

```bash
# Standard restart sequence
sudo systemctl restart proxmox-mcp

# Manual container restart
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml restart mcp-server

# Full restart (if standard restart fails)
sudo systemctl stop proxmox-mcp
sudo docker-compose -f docker-compose.prod.yml down
sudo systemctl start proxmox-mcp

# Verify restart worked
curl http://localhost:8080/health
sudo docker-compose -f docker-compose.prod.yml ps
```

#### Service Recovery After System Reboot

```bash
# Services should auto-start, but if not:
sudo systemctl start docker
sudo systemctl start proxmox-mcp

# Enable pveproxy if it's disabled
sudo systemctl enable pveproxy
sudo systemctl start pveproxy

# Check service status
sudo systemctl status proxmox-mcp
sudo systemctl status pveproxy
sudo systemctl status docker
```

#### Health Monitoring Commands

```bash
# Quick health check
curl http://localhost:8080/health
# Expected: {"status":"healthy"}

# MCP endpoint check  
curl http://localhost:8080/api/mcp
# Should not return 404

# Container status
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml ps
# All services should show "Up"

# Log monitoring
sudo docker-compose -f docker-compose.prod.yml logs -f mcp-server
```

### Quick Validation Commands

```bash
# Test practical admin deployment
sudo -u claude-user sudo qm list  # Should work
sudo -u claude-user sudo systemctl status pveproxy  # Should work
sudo -u claude-user sudo userdel root  # Should be blocked

# Test MCP functionality
curl http://localhost:8080/health  # Should return {"status":"healthy"}
curl http://localhost:8080/api/mcp  # Should not return 404

# Test SSH key access
sudo chown -R 1000:1000 /opt/proxmox-mcp/keys/
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml exec mcp-server ls -la /app/keys/
# Should show files owned by mcpuser

# Test SSH connectivity from container
sudo docker-compose -f docker-compose.prod.yml exec mcp-server ssh -i /app/keys/ssh_key -o BatchMode=yes claude-user@localhost whoami
# Should return: claude-user

# Test Claude Code connection
claude mcp list  # Should show proxmox-production
```

### Self-Diagnosis Checklist

Before seeking help, verify:

**Basic System Status:**
- [ ] Service is running: `sudo systemctl status proxmox-mcp`
- [ ] Containers are healthy: `cd /opt/proxmox-mcp/docker && sudo docker-compose -f docker-compose.prod.yml ps`
- [ ] Health endpoint responds: `curl http://localhost:8080/health`
- [ ] MCP endpoint responds: `curl http://localhost:8080/api/mcp`

**SSH and Permissions:**
- [ ] SSH keys have correct ownership: `ls -la /opt/proxmox-mcp/keys/` (should show 1000:1000)
- [ ] SSH connectivity works: `ssh -i /opt/proxmox-mcp/keys/ssh_key claude-user@localhost "whoami"`
- [ ] Practical admin permissions work: `sudo -u claude-user sudo qm list`

**Claude Code Integration:**
- [ ] Claude CLI shows server: `claude mcp list` shows proxmox-production
- [ ] MCP tools work in Claude Code: Try "Please execute the command 'whoami'"
- [ ] No permission errors in tool responses

**Network and Firewall:**
- [ ] Network connectivity: Can access from client machine
- [ ] Firewall allows required ports: 22, 8080, 80, 443
- [ ] Disk space available: `df -h`
- [ ] No resource exhaustion: `free -h`, `top`

**If All Checks Pass But Issues Persist:**
- Check container logs: `cd /opt/proxmox-mcp/docker && sudo docker-compose -f docker-compose.prod.yml logs mcp-server`
- Re-run installation: `cd /opt/proxmox-mcp && sudo ./scripts/install/install.sh`
- Test end-to-end: Start fresh Claude Code session and try basic commands

## Production Deployment Status

### ✅ What Should Work After All Fixes

**Installation Process:**
```bash
# Single command installation from fresh Proxmox
cd /opt/proxmox-mcp && sudo ./scripts/install/install.sh
```

**Expected Outcome:**
- ✅ Docker container running and healthy
- ✅ SSH keys properly configured and accessible (1000:1000 ownership)
- ✅ MCP server responding on http://IP:8080/api/mcp (not /api)
- ✅ execute_command tool validated and working during installation
- ✅ All prerequisites installed (Docker, Node.js, etc.)
- ✅ Firewall configured for port 8080 access
- ✅ Client connection instructions generated with correct endpoint

**Claude Code Integration:**
```bash
# Connect Claude Code to MCP server (use correct endpoint)
claude mcp add --transport http proxmox-production http://SERVER_IP:8080/api/mcp
claude mcp list  # Verify connection shows proxmox-production
```

**Available MCP Tools:**
- `execute_command(command, timeout)` - Run shell commands via SSH
- `list_vms()` - List all VMs via Proxmox API
- `vm_status(vmid, node)` - Get VM status
- `vm_action(vmid, node, action)` - Start/stop/restart VMs
- `node_status(node)` - Get Proxmox node information  
- `proxmox_api(method, path, data)` - Direct API calls

### System Recovery Capabilities

**Container Management:**
- Auto-restart after system reboot via systemd
- Health monitoring at `/health` endpoint
- Log access via `docker-compose logs -f mcp-server`
- pveproxy auto-enabled and started

**Security Recovery:**
- Practical admin model enables full VM/LXC/Docker management
- Catastrophic operations blocked (userdel root, pvecm delnode, etc.)
- Comprehensive sudoers configuration with audit logging

### Emergency Recovery Commands

```bash
# If MCP connection fails, try these in order:

# 1. Check endpoint (most common issue)
curl http://localhost:8080/api/mcp  # Should not return 404

# 2. Fix SSH key permissions
sudo chown -R 1000:1000 /opt/proxmox-mcp/keys/
sudo systemctl restart proxmox-mcp

# 3. Restart services
sudo systemctl restart proxmox-mcp

# 4. Full container rebuild (if needed)
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml down
sudo docker-compose -f docker-compose.prod.yml build --no-cache
sudo docker-compose -f docker-compose.prod.yml up -d

# 5. Re-run installation (last resort)
cd /opt/proxmox-mcp && sudo ./scripts/install/install.sh
```

Most issues can be resolved by following the diagnostic steps and solutions in this guide. The practical admin model enables real administrative work while maintaining security. All major fixes have been applied and the system should work out-of-the-box after installation.