# Proxmox MCP - Troubleshooting Guide

**Comprehensive troubleshooting for common issues and solutions**

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

### Issue: SSH Key Generation/Deployment Fails

**Symptoms:**
- Key generation fails
- SSH key deployment fails
- Permission denied on key files

**Solutions:**

```bash
# Manual key generation
sudo rm -f /opt/proxmox-mcp/keys/claude_proxmox_key*
sudo ssh-keygen -t ed25519 -f /opt/proxmox-mcp/keys/claude_proxmox_key -C "proxmox-mcp-manual" -N ""
sudo chmod 600 /opt/proxmox-mcp/keys/claude_proxmox_key
sudo chmod 644 /opt/proxmox-mcp/keys/claude_proxmox_key.pub

# Manual key deployment
ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key.pub claude-user@YOUR_PROXMOX_IP

# Alternative: Manual key copy
ssh root@YOUR_PROXMOX_IP "mkdir -p /home/claude-user/.ssh"
scp /opt/proxmox-mcp/keys/claude_proxmox_key.pub root@YOUR_PROXMOX_IP:/home/claude-user/.ssh/authorized_keys
ssh root@YOUR_PROXMOX_IP "chown claude-user:claude-user /home/claude-user/.ssh/authorized_keys"
ssh root@YOUR_PROXMOX_IP "chmod 600 /home/claude-user/.ssh/authorized_keys"

# Test SSH connection
ssh -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@YOUR_PROXMOX_IP "whoami"
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

**Diagnosis:**

```bash
# Check container status
sudo docker ps -a
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml ps

# Check container logs
sudo docker logs proxmox-mcp-server
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml logs mcp-server

# Check image availability
sudo docker images | grep proxmox-mcp
```

**Solutions:**

```bash
# Rebuild container
cd /opt/proxmox-mcp
sudo docker-compose down
sudo docker-compose build --no-cache
sudo docker-compose up -d

# Check for port conflicts
sudo netstat -tlnp | grep 8080
sudo lsof -i :8080

# Fix permission issues
sudo chown -R root:docker /opt/proxmox-mcp
sudo chmod -R 755 /opt/proxmox-mcp

# Restart Docker service
sudo systemctl restart docker
sudo systemctl restart proxmox-mcp
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

### Issue: Health Check Endpoint Fails

**Symptoms:**
- curl http://localhost:8080/health fails
- 404 or connection refused errors
- Service appears running but unresponsive

**Diagnosis:**

```bash
# Check if port is bound
sudo netstat -tlnp | grep 8080
sudo ss -tlnp | grep 8080

# Check container internal health
sudo docker exec proxmox-mcp-server curl http://localhost:8080/health

# Check container networking
sudo docker network ls
sudo docker network inspect mcp-network
```

**Solutions:**

```bash
# Restart services
sudo systemctl restart proxmox-mcp

# Check internal connectivity
sudo docker exec proxmox-mcp-server netstat -tlnp

# Fix networking issues
sudo docker network prune
sudo docker-compose down
sudo docker-compose up -d

# Check firewall
sudo ufw status
sudo iptables -L INPUT | grep 8080
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

### Issue: Sudo Configuration Problems

**Symptoms:**
- Commands blocked unexpectedly
- Sudo permission denied
- Security validation fails

**Diagnosis:**

```bash
# Check sudoers configuration
sudo visudo -c -f /etc/sudoers.d/claude-user

# Test sudo access
sudo -u claude-user sudo -l

# Check command blocking
sudo -u claude-user sudo /usr/sbin/qm list 2>&1
```

**Solutions:**

```bash
# Redeploy security configuration
sudo ./deploy-enhanced-security.sh

# Manual sudoers fix
sudo visudo -f /etc/sudoers.d/claude-user

# Test specific command
sudo -u claude-user sudo /usr/sbin/qm list

# Check security logs
sudo tail -f /var/log/sudo-claude-user.log
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

### Issue: MCP Tools Not Available

**Symptoms:**
- No MCP tools visible in Claude Code
- mcp__proxmox-production__ prefix missing
- Tools list empty

**Diagnosis:**

```bash
# Test MCP endpoint
curl -X POST http://YOUR_PROXMOX_IP:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'

# Check Claude Code configuration
cat ~/.claude.json

# Verify JSON syntax
python3 -m json.tool ~/.claude.json
```

**Solutions:**

```bash
# Fix Claude Code configuration
tee ~/.claude.json << 'EOF'
{
  "mcpServers": {
    "proxmox-production": {
      "type": "http",
      "url": "http://YOUR_PROXMOX_IP:8080/api/mcp",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    }
  }
}
EOF

# Restart Claude Code
# Close all Claude Code instances and restart

# Test MCP connection
curl -X POST http://YOUR_PROXMOX_IP:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"1"}'
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
# Stop all services
sudo systemctl stop proxmox-mcp
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml down

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

### Self-Diagnosis Checklist

Before seeking help, verify:

- [ ] Service is running: `sudo systemctl status proxmox-mcp`
- [ ] Containers are healthy: `sudo docker ps`
- [ ] Health endpoint responds: `curl http://localhost:8080/health`
- [ ] SSH connectivity works: `ssh -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@YOUR_PROXMOX_IP "whoami"`
- [ ] API token is valid: Test with curl command
- [ ] Claude Code configuration is correct: Valid JSON syntax
- [ ] Network connectivity: Can access from client machine
- [ ] Firewall allows required ports: 22, 8080, 80, 443
- [ ] Disk space available: `df -h`
- [ ] No resource exhaustion: `free -h`, `top`

Most issues can be resolved by following the diagnostic steps and solutions in this guide. For persistent issues, collecting the diagnostic information above will help identify the root cause.