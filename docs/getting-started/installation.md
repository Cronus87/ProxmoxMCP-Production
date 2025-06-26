# Proxmox MCP Server - Complete Installation Guide

**Enterprise-Grade Proxmox Management for Claude Code**

## Overview

The Proxmox MCP (Model Context Protocol) Server provides secure, enterprise-ready Proxmox VE management capabilities accessible from any Claude Code project. This guide covers complete installation from prerequisites through verification.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Requirements](#system-requirements)
3. [Single-Command Installation](#single-command-installation)
4. [Manual Installation](#manual-installation)
5. [Configuration](#configuration)
6. [Verification](#verification)
7. [Claude Code Setup](#claude-code-setup)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

**Proxmox Host:**
- Proxmox VE 7.0+ or 8.0+
- Debian-based operating system (Debian 11/12, Ubuntu 20.04/22.04)
- Docker 20.10+ and Docker Compose 2.0+
- 4GB+ RAM, 20GB+ disk space
- Network connectivity to internet

**Client Environment:**
- Claude Code (latest version)
- Network access to Proxmox host

### Network Requirements

**Required Ports:**
- **SSH**: 22 (for management)
- **HTTP**: 80 (redirects to HTTPS)
- **HTTPS**: 443 (MCP API access)
- **Proxmox Web**: 8006 (API access)

**Optional Monitoring Ports:**
- **Grafana**: 3000
- **Prometheus**: 9090

### Access Requirements

**Proxmox API Access:**
- Root access or dedicated API user
- API token with appropriate permissions
- SSH access for initial setup

---

## Single-Command Installation

### Quick Start (Recommended)

The installation script provides fully automated deployment with guided configuration:

```bash
# 1. Download and run installer
curl -fsSL https://raw.githubusercontent.com/YOUR-REPO/ProxmoxMCP-Production/main/install.sh | sudo bash

# OR clone repository first
git clone https://github.com/YOUR-REPO/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production
sudo ./install.sh
```

### Installation Process

The installer performs these phases automatically:

**Phase 1: System Preparation**
- Validates root privileges and OS compatibility
- Tests network connectivity
- Installs Docker and prerequisites
- Creates directory structure

**Phase 2: Configuration Discovery**
- Auto-discovers Proxmox servers on network
- Collects configuration parameters interactively
- Generates SSH keys and configuration files
- Validates Proxmox API connectivity

**Phase 3: Security Deployment**
- Creates restricted claude-user account
- Deploys bulletproof security configuration (85+ controls)
- Runs comprehensive security validation
- Sets up security monitoring

**Phase 4: Container Deployment**
- Builds/pulls container images
- Starts MCP server and reverse proxy
- Configures systemd service
- Waits for services to be ready

**Phase 5: Client Configuration**
- Generates Claude Code configuration
- Tests MCP connection
- Verifies tool availability

**Phase 6: Final Validation**
- Tests end-to-end connectivity
- Validates security implementation
- Generates installation report

### Interactive Configuration

During installation, you'll be prompted for:

```
=== PROXMOX MCP CONFIGURATION ===

Proxmox host IP address: [auto-discovered or manual entry]
SSH user for MCP operations [claude-user]: 
SSH port [22]: 
Proxmox API user [root@pam]: 
Proxmox API token name [claude-mcp]: 
API token value: [enter from Proxmox web interface]
MCP server port [8080]: 
Enable monitoring dashboards? [y/N]: 
```

### Post-Installation

After successful installation:

```bash
# Service endpoints available:
# Health: http://localhost:8080/health
# API Docs: http://localhost:8080/docs  
# MCP Endpoint: http://localhost:8080/api/mcp

# Grafana (if enabled): http://localhost:3000 (admin/admin)
# Prometheus (if enabled): http://localhost:9090

# Installation report generated at:
# /opt/proxmox-mcp/installation-report-[ID].md
```

---

## Manual Installation

### Step 1: System Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install prerequisites
sudo apt install -y curl wget git jq unzip ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https netcat-openbsd dnsutils

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker
```

### Step 2: Create Directory Structure

```bash
# Create installation directories
sudo mkdir -p /opt/proxmox-mcp/{config,keys,logs,caddy,monitoring}
sudo mkdir -p /var/log/sudo-io/claude-user
sudo chmod 755 /opt/proxmox-mcp
```

### Step 3: Clone Repository

```bash
cd /opt/proxmox-mcp
sudo git clone https://github.com/YOUR-REPO/ProxmoxMCP-Production.git .
sudo chown -R root:docker /opt/proxmox-mcp
```

### Step 4: Generate SSH Keys

```bash
# Generate SSH key pair
sudo ssh-keygen -t ed25519 -f /opt/proxmox-mcp/keys/claude_proxmox_key -C "proxmox-mcp-$(date +%Y%m%d)" -N ""
sudo chmod 600 /opt/proxmox-mcp/keys/claude_proxmox_key
sudo chmod 644 /opt/proxmox-mcp/keys/claude_proxmox_key.pub

# Display public key for manual installation
echo "Add this public key to Proxmox server:"
sudo cat /opt/proxmox-mcp/keys/claude_proxmox_key.pub

# Copy to Proxmox server
ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key.pub claude-user@YOUR_PROXMOX_IP
```

### Step 5: Configuration

```bash
# Create environment configuration
sudo tee /opt/proxmox-mcp/.env << EOF
# Container Configuration
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
PROXMOX_TOKEN_VALUE=YOUR_API_TOKEN
PROXMOX_VERIFY_SSL=false

# Feature Configuration
ENABLE_PROXMOX_API=true
ENABLE_DANGEROUS_COMMANDS=false

# MCP Server Configuration
MCP_HOST=0.0.0.0
MCP_PORT=8080
EOF

sudo chmod 640 /opt/proxmox-mcp/.env
```

### Step 6: Deploy Security Configuration

```bash
# Create claude-user account (on Proxmox server)
ssh root@YOUR_PROXMOX_IP "useradd -m -s /bin/bash claude-user"
ssh root@YOUR_PROXMOX_IP "usermod -aG docker claude-user"

# Deploy enhanced security configuration
sudo ./deploy-enhanced-security.sh

# Validate security implementation
sudo -u claude-user ./comprehensive-security-validation.sh
```

### Step 7: Start Services

```bash
# Copy Docker Compose configuration
sudo cp docker/docker-compose.prod.yml /opt/proxmox-mcp/docker-compose.yml

# Start services
cd /opt/proxmox-mcp
sudo docker-compose up -d

# Create systemd service
sudo tee /etc/systemd/system/proxmox-mcp.service << EOF
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

sudo systemctl daemon-reload
sudo systemctl enable proxmox-mcp
sudo systemctl start proxmox-mcp
```

---

## Configuration

### Environment Variables

Core configuration in `/opt/proxmox-mcp/.env`:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `SSH_HOST` | Proxmox server IP | - | ✅ |
| `SSH_USER` | SSH user for operations | claude-user | ✅ |
| `SSH_KEY_PATH` | SSH private key path | /app/keys/claude_proxmox_key | ✅ |
| `PROXMOX_HOST` | Proxmox API host | - | ✅ |
| `PROXMOX_USER` | Proxmox API user | root@pam | ✅ |
| `PROXMOX_TOKEN_NAME` | API token name | claude-mcp | ✅ |
| `PROXMOX_TOKEN_VALUE` | API token value | - | ✅ |
| `MCP_PORT` | MCP server port | 8080 | ❌ |
| `ENABLE_PROXMOX_API` | Enable API features | true | ❌ |
| `LOG_LEVEL` | Logging level | INFO | ❌ |

### Proxmox API Token Setup

1. **Access Proxmox Web Interface:**
   ```
   https://YOUR_PROXMOX_IP:8006
   ```

2. **Create API Token:**
   - Navigate to: **Datacenter → Permissions → API Tokens**
   - Click **Add**
   - User: `root@pam`
   - Token ID: `claude-mcp`
   - **Uncheck** "Privilege Separation" for full access
   - Copy the generated token value

3. **Update Configuration:**
   ```bash
   sudo sed -i 's/PROXMOX_TOKEN_VALUE=.*/PROXMOX_TOKEN_VALUE=YOUR_TOKEN_HERE/' /opt/proxmox-mcp/.env
   ```

### Security Configuration

The system implements bulletproof security with 85+ controls:

**Key Security Features:**
- ✅ **Root Protection**: Prevents any modification to root@pam user
- ✅ **Command Filtering**: Blocks 85+ dangerous command patterns
- ✅ **Environment Security**: Prevents variable manipulation attacks
- ✅ **Privilege Control**: Prevents escalation and shell access
- ✅ **Audit Logging**: Complete I/O and command logging

**Security Files:**
- `/etc/sudoers.d/claude-user` - Enhanced sudoers configuration
- `/var/log/sudo-claude-user.log` - Command audit log
- `/var/log/sudo-io/claude-user/` - I/O session logs

---

## Verification

### Service Health Check

```bash
# Check service status
sudo systemctl status proxmox-mcp

# Verify containers are running
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml ps

# Test health endpoint
curl http://localhost:8080/health
```

Expected health response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "1.0.0"
}
```

### MCP API Verification

```bash
# Test MCP endpoint
curl -X POST http://localhost:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'
```

Expected response should show available tools:
```json
{
  "jsonrpc": "2.0",
  "id": "test",
  "result": {
    "tools": [
      {"name": "execute_command", "description": "Execute a shell command..."},
      {"name": "list_vms", "description": "List all VMs..."},
      {"name": "vm_status", "description": "Get detailed VM status..."},
      {"name": "vm_action", "description": "Perform VM actions..."},
      {"name": "node_status", "description": "Get node status..."},
      {"name": "proxmox_api", "description": "Direct API calls..."}
    ]
  }
}
```

### Security Validation

```bash
# Run security test suite
sudo -u claude-user ./comprehensive-security-validation.sh

# Check blocked operations (should fail)
sudo -u claude-user sudo /usr/sbin/pveum user modify root@pam --test

# Check allowed operations (should work)
sudo -u claude-user sudo /usr/sbin/qm list
```

### Connectivity Tests

```bash
# Test SSH connectivity
ssh -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@YOUR_PROXMOX_IP "echo 'SSH test successful'"

# Test Proxmox API
curl -k -H "Authorization: PVEAPIToken=root@pam!claude-mcp=YOUR_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version
```

---

## Claude Code Setup

### Global Configuration

Add to your `~/.claude.json` for universal access:

```json
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "http://YOUR_PROXMOX_IP:8080/api/mcp",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    }
  }
}
```

### Project-Specific Configuration

For specific projects, add to project's `.claude.json`:

```json
{
  "mcpServers": {
    "proxmox-production": {
      "type": "http", 
      "url": "http://YOUR_PROXMOX_IP:8080/api/mcp",
      "name": "Proxmox Production Environment",
      "description": "Production Proxmox management tools"
    }
  }
}
```

### HTTPS Configuration (Recommended)

For external access with SSL:

```json
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "https://YOUR_DOMAIN/api/mcp",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    }
  }
}
```

### Verification

```bash
# Start Claude Code from any directory
cd /any/project/directory
claude

# Verify MCP tools are available
# The following tools should be accessible:
# - mcp__proxmox-production__execute_command
# - mcp__proxmox-production__list_vms  
# - mcp__proxmox-production__vm_status
# - mcp__proxmox-production__vm_action
# - mcp__proxmox-production__node_status
# - mcp__proxmox-production__proxmox_api
```

---

## Troubleshooting

### Installation Issues

**Problem: Prerequisites installation fails**
```bash
# Check OS compatibility
cat /etc/os-release

# Manual Docker installation
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

**Problem: SSH key deployment fails**
```bash
# Verify key generation
ls -la /opt/proxmox-mcp/keys/
ssh-keygen -l -f /opt/proxmox-mcp/keys/claude_proxmox_key.pub

# Manual key deployment
ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key.pub claude-user@YOUR_PROXMOX_IP

# Test SSH connection
ssh -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@YOUR_PROXMOX_IP "whoami"
```

### Service Issues

**Problem: Container fails to start**
```bash
# Check Docker logs
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml logs mcp-server

# Check container status
sudo docker ps -a

# Restart services
sudo systemctl restart proxmox-mcp
```

**Problem: Health check fails**
```bash
# Check if port is bound
sudo netstat -tlnp | grep 8080

# Test internal connectivity
curl http://localhost:8080/health

# Check container networking
sudo docker network ls
sudo docker network inspect mcp-network
```

### API Connection Issues

**Problem: Proxmox API authentication fails**
```bash
# Verify API token
curl -k -H "Authorization: PVEAPIToken=root@pam!claude-mcp=YOUR_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version

# Check token permissions in Proxmox web interface
# Datacenter → Permissions → API Tokens

# Regenerate token if needed
```

**Problem: MCP tools not available in Claude Code**
```bash
# Verify MCP endpoint responds
curl -X POST http://YOUR_PROXMOX_IP:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'

# Check Claude Code configuration
cat ~/.claude.json

# Restart Claude Code
```

### Security Issues

**Problem: Commands being blocked unexpectedly**
```bash
# Check security logs
sudo tail -f /var/log/sudo-claude-user.log

# Verify sudoers configuration
sudo visudo -c -f /etc/sudoers.d/claude-user

# Test specific command
sudo -u claude-user sudo -l | grep YOUR_COMMAND
```

**Problem: Security validation fails**
```bash
# Run validation with verbose output
sudo -u claude-user ./comprehensive-security-validation.sh -v

# Check for configuration issues
sudo visudo -c

# Review security configuration
sudo cat /etc/sudoers.d/claude-user
```

### Network Issues

**Problem: External access not working**
```bash
# Check firewall rules
sudo ufw status
sudo iptables -L

# Verify port binding
sudo netstat -tlnp | grep -E "(80|443|8080)"

# Test from external host
curl http://YOUR_PROXMOX_IP:8080/health
```

### Log Analysis

**System Logs:**
```bash
# Service logs
sudo journalctl -u proxmox-mcp -f

# Docker logs
sudo docker-compose -f /opt/proxmox-mcp/docker-compose.yml logs -f

# Security logs
sudo tail -f /var/log/sudo-claude-user.log
sudo tail -f /var/log/auth.log | grep claude-user
```

**Application Logs:**
```bash
# MCP server logs
sudo docker logs proxmox-mcp-server

# Reverse proxy logs
sudo docker logs mcp-reverse-proxy

# Installation logs
sudo tail -f /var/log/proxmox-mcp-install.log
```

---

## Support Resources

### Documentation
- **Installation Report**: `/opt/proxmox-mcp/installation-report-[ID].md`
- **Security Analysis**: `COMPREHENSIVE-SECURITY-ANALYSIS.md`
- **Quick Start Guide**: `docs/QUICK-START.md`
- **Administrator Guide**: `docs/ADMINISTRATOR-GUIDE.md`

### Monitoring
- **Health Endpoint**: `http://YOUR_PROXMOX_IP:8080/health`
- **API Documentation**: `http://YOUR_PROXMOX_IP:8080/docs`
- **Grafana Dashboard**: `http://YOUR_PROXMOX_IP:3000` (if enabled)

### Maintenance Commands
```bash
# Update system
sudo ./install.sh

# Restart services
sudo systemctl restart proxmox-mcp

# View status
sudo systemctl status proxmox-mcp

# Run security validation
sudo -u claude-user ./comprehensive-security-validation.sh

# Check logs
sudo journalctl -u proxmox-mcp --since today
```

---

**Installation Complete!** 

Your Proxmox MCP server is now ready for universal access from any Claude Code project.