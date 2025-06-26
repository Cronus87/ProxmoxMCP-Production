# Proxmox MCP Server - Complete Installation Guide

**Production-Ready Proxmox Management for Claude Code with Practical Admin Model**

## Overview

The Proxmox MCP (Model Context Protocol) Server provides secure, production-ready Proxmox VE management capabilities accessible from any Claude Code project. This system implements a **Practical Admin Model** that enables real administrative work while protecting against only catastrophic operations.

**Key Features:**
- ✅ **Single-Command Installation**: `sudo ./scripts/install/install.sh` (v2.0 with all fixes)
- ✅ **Practical Admin Model**: Enable real admin work, block only catastrophic operations
- ✅ **Complete Docker Integration**: VM/LXC and Docker image mapping with host access
- ✅ **Production-Ready Deployment**: Auto-restart, SSH key ownership fixes, comprehensive validation
- ✅ **End-to-End MCP Tool Testing**: Real execute_command validation during installation
- ✅ **Fixed MCP Endpoint**: Correct `/api/mcp` endpoint configuration
- ✅ **Container Permission Fixes**: SSH keys with proper 1000:1000 ownership

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
- **SSH**: 22 (for claude-user access)
- **MCP HTTP**: 8080 (MCP API access)
- **Proxmox Web**: 8006 (API access)

**Optional Ports:**
- **HTTP**: 80 (redirects to HTTPS)
- **HTTPS**: 443 (SSL termination)
- **Grafana**: 3000 (monitoring)
- **Prometheus**: 9090 (metrics)

### Access Requirements

**Proxmox API Access:**
- Root access or dedicated API user
- API token with appropriate permissions
- SSH access for initial setup

---

## Single-Command Installation

### Quick Start (Recommended)

The installation script provides fully automated deployment with practical admin configuration:

```bash
# Clone repository and install
git clone https://github.com/YOUR-REPO/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production
sudo ./scripts/install/install.sh
```

**What the installer does (v2.0 with all fixes applied):**
- ✅ Creates claude-user with practical admin permissions (enable real admin work)
- ✅ Generates SSH keys as `/keys/ssh_key` with correct container ownership (1000:1000)
- ✅ Deploys Docker containers with proper volume mounting and health checks
- ✅ Validates MCP tools with real execute_command testing during installation
- ✅ Configures firewall for port 8080 and systemd services
- ✅ Tests end-to-end functionality with actual MCP tool calls
- ✅ Provides correct client connection instructions with `/api/mcp` endpoint
- ✅ Validates SSH key accessibility from container mcpuser

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

**Phase 3: Practical Admin Security Deployment**
- Creates claude-user account with practical admin permissions
- Deploys practical admin sudoers configuration ("Enable real admin work, block only catastrophic operations")
- Enables full system administration while blocking only destructive actions
- Sets up SSH keys with correct container ownership (1000:1000 for mcpuser)

**Phase 4: Container Deployment**
- Builds/pulls container images
- Starts MCP server and reverse proxy
- Configures systemd service
- Waits for services to be ready

**Phase 5: Client Configuration**
- Generates Claude Code configuration with correct `/api/mcp` endpoint
- Tests MCP connection with real tool calls
- Verifies all 6 MCP tools are available and functional

**Phase 6: Final Validation**
- Tests end-to-end connectivity with execute_command validation
- Validates security implementation with real permission tests
- Generates installation report with connection instructions
- Confirms SSH key accessibility from container

### Interactive Configuration

During installation, you'll be prompted for:

```
=== PROXMOX MCP CONFIGURATION ===

Proxmox server IP/hostname [auto-detected]: 
SSH hostname for claude-user access [same as above]: 
API Token Name [claude-mcp]: 
API Token Value: [enter from Proxmox web interface]
```

**API Token Setup Instructions:**
1. Go to https://YOUR_PROXMOX_IP:8006
2. Navigate to Datacenter → Permissions → API Tokens
3. Click 'Add' to create new token
4. Set User: root@pam, Token ID: claude-mcp
5. **Uncheck 'Privilege Separation'** for full access
6. Copy the generated token value

### Post-Installation

After successful installation:

```bash
# Service endpoints available:
# Health: http://SERVER_IP:8080/health
# MCP Endpoint: http://SERVER_IP:8080/api/mcp (CORRECT ENDPOINT)

# Key files and directories:
# Environment: /opt/proxmox-mcp/docker/.env
# SSH Keys: /opt/proxmox-mcp/keys/ssh_key (1000:1000 ownership for container)
# Container logs: cd /opt/proxmox-mcp/docker && docker-compose -f docker-compose.prod.yml logs -f

# Client connection (FIXED ENDPOINT):
claude mcp add --transport http proxmox-production http://SERVER_IP:8080/api/mcp
```

### System Status Verification

```bash
# Check service status
sudo systemctl status proxmox-mcp

# Check container health
cd /opt/proxmox-mcp/docker && sudo docker-compose -f docker-compose.prod.yml ps

# Test MCP tools
curl http://localhost:8080/health

# Test practical admin permissions
sudo -u claude-user sudo systemctl status pveproxy
sudo -u claude-user sudo qm list
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
# Generate SSH key pair (FIXED: correct naming for container)
sudo ssh-keygen -t ed25519 -f /opt/proxmox-mcp/keys/ssh_key -C "proxmox-mcp-$(date +%Y%m%d)" -N ""
sudo chown 1000:1000 /opt/proxmox-mcp/keys/ssh_key*  # CRITICAL: container ownership
sudo chmod 600 /opt/proxmox-mcp/keys/ssh_key
sudo chmod 644 /opt/proxmox-mcp/keys/ssh_key.pub

# Display public key for manual installation
echo "Add this public key to Proxmox server:"
sudo cat /opt/proxmox-mcp/keys/ssh_key.pub

# Copy to Proxmox server (FIXED: correct key name)
ssh-copy-id -i /opt/proxmox-mcp/keys/ssh_key.pub claude-user@YOUR_PROXMOX_IP
```

### Step 5: Configuration

```bash
# Create environment configuration
sudo tee /opt/proxmox-mcp/.env << EOF
# Container Configuration
IMAGE_TAG=latest
LOG_LEVEL=INFO

# SSH Configuration (FIXED: correct container key path)
SSH_TARGET=proxmox
SSH_HOST=YOUR_PROXMOX_IP
SSH_USER=claude-user
SSH_PORT=22
SSH_KEY_PATH=/app/keys/ssh_key

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
| `SSH_KEY_PATH` | SSH private key path | /app/keys/ssh_key | ✅ |
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

### Practical Admin Configuration

The system implements a **Practical Admin Model** designed for real administrative work:

**Philosophy: Enable Real Admin Work, Block Only Catastrophic Actions**

**What's Allowed (Full Access):**
- ✅ **Complete System Administration**: /usr/bin/*, /usr/sbin/*, /bin/*, /sbin/*
- ✅ **VM/LXC Management**: qm, pct, pvesm, pvesh commands
- ✅ **Docker Management**: Full container and image operations
- ✅ **Service Management**: systemctl operations
- ✅ **Network Configuration**: Standard networking tools
- ✅ **File System Operations**: Standard file operations
- ✅ **No TTY Requirement**: Defaults:claude-user !requiretty for SSH access

**What's Blocked (Catastrophic Operations Only):**
- ❌ **Cluster Destruction**: pvecm delnode
- ❌ **Root Account Manipulation**: userdel root, usermod root
- ❌ **PVE Root User Deletion**: pveum user delete root@pam
- ❌ **Storage Destruction**: pvesm remove
- ❌ **Critical Bridge Deletion**: ip link delete vmbr0
- ❌ **Core Service Disruption**: systemctl stop pveproxy/pvedaemon/pvestatd

**Key Files:**
- `/etc/sudoers.d/claude-user` - Practical admin sudoers configuration
- `/opt/proxmox-mcp/keys/ssh_key` - SSH key for container access (1000:1000 ownership)
- `/opt/proxmox-mcp/docker/.env` - Environment configuration
- `/opt/proxmox-mcp/docker/docker-compose.prod.yml` - Container orchestration

---

## Verification

### Service Health Check

```bash
# Check service status
sudo systemctl status proxmox-mcp

# Verify containers are running (FIXED: correct compose file path)
cd /opt/proxmox-mcp/docker && sudo docker-compose -f docker-compose.prod.yml ps

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
# Test SSH connectivity (FIXED: correct key name)
ssh -i /opt/proxmox-mcp/keys/ssh_key claude-user@YOUR_PROXMOX_IP "echo 'SSH test successful'"

# Test Proxmox API
curl -k -H "Authorization: PVEAPIToken=root@pam!claude-mcp=YOUR_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version
```

---

## Claude Code Setup

### Quick Connection (Recommended)

Use the Claude Code CLI to connect:

```bash
# Add MCP server (CORRECT ENDPOINT: /api/mcp)
claude mcp add --transport http proxmox-production http://YOUR_PROXMOX_IP:8080/api/mcp

# Verify connection
claude mcp list

# Start using MCP tools in any Claude Code session
claude
```

### Manual Configuration

Add to your `~/.claude.json` for universal access:

```json
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
```

**Note**: The above configuration uses stdio transport with the fetch server. For direct HTTP transport, use the Claude CLI method shown above.

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

### Available MCP Tools

Once connected, these tools are available in Claude Code:

**Core Tools:**
- **`execute_command`** - Run shell commands via SSH with practical admin permissions
- **`list_vms`** - List all VMs via Proxmox API
- **`vm_status`** - Get detailed VM status and configuration
- **`vm_action`** - Start, stop, restart, shutdown VMs
- **`node_status`** - Get Proxmox node information and resources
- **`proxmox_api`** - Direct Proxmox API calls for advanced operations

**Example Usage in Claude Code:**
```
# List all VMs
Please list all VMs on the Proxmox server

# Check node status
Show me the current node status and resource usage

# Execute admin commands with practical admin permissions
Please check if the pveproxy service is running
Can you restart the pveproxy service?
Show me the Docker images available on the host

# Docker operations (complete integration)
Show me all running Docker containers on the host
Pull the latest nginx image and create a new container
Map container ports to host and show me the running services

# VM/LXC management
Create a new Ubuntu 22.04 VM with 4GB RAM and 50GB disk
Start VM 100 and show me its status
Create an LXC container with Docker installed

# Real admin work examples
Install a new package using apt
Check disk usage and clean up log files
Configure firewall rules for a new service
Update system packages and restart required services
```

### Verification

```bash
# Test MCP connection
claude mcp list
# Should show: proxmox-production

# Start Claude Code and test tools
claude
# In Claude Code: "Please execute the command 'systemctl status pveproxy'"
```

---

## Troubleshooting

### Recent Fixes Applied (install.sh v2.0)

**✅ RESOLVED ISSUES:**

1. **SSH Key Path Mismatch** 
   - **Problem**: Container expected `/app/keys/ssh_key` but install.sh created different name
   - **Fix**: Generate SSH key as `$KEYS_DIR/ssh_key` with correct container ownership (1000:1000)
   - **Status**: ✅ FIXED - Keys now accessible to container mcpuser

2. **MCP Endpoint Configuration**
   - **Problem**: Client instructions referenced wrong `/api` endpoint 
   - **Fix**: All instructions now correctly use `/api/mcp` endpoint
   - **Status**: ✅ FIXED - MCP connection works immediately

3. **Missing End-to-End Validation**
   - **Problem**: Install.sh only tested health endpoint, not actual MCP tools
   - **Fix**: Added real execute_command testing during installation
   - **Status**: ✅ FIXED - Installation fails if MCP tools don't work

4. **Container Permission Issues**
   - **Problem**: SSH keys had wrong ownership for container user
   - **Fix**: Set keys to 1000:1000 (mcpuser) during key generation
   - **Status**: ✅ FIXED - Container can access SSH keys

5. **Practical Admin Model Implementation**
   - **Problem**: Previous restrictive sudo configuration blocked real admin work
   - **Fix**: New philosophy "Enable real admin work, block only catastrophic operations"
   - **Status**: ✅ FIXED - Full system administration with practical restrictions

6. **Docker Integration Issues**
   - **Problem**: Limited Docker management capabilities
   - **Fix**: Complete Docker integration with host volume mapping
   - **Status**: ✅ FIXED - Full Docker image and container management

### Installation Issues

**Problem: Installation script fails**
```bash
# Check if running from correct directory
pwd
# Should be in ProxmoxMCP-Production root

# Check prerequisites
which docker
which pvesh

# Re-run with verbose logging
sudo bash -x ./scripts/install/install.sh
```

**Problem: SSH key access fails**
```bash
# Check key ownership (CRITICAL: must be 1000:1000 for container)
ls -la /opt/proxmox-mcp/keys/

# Fix key ownership if wrong (FIXED: correct ownership)
sudo chown -R 1000:1000 /opt/proxmox-mcp/keys/
sudo chmod 600 /opt/proxmox-mcp/keys/ssh_key
sudo chmod 644 /opt/proxmox-mcp/keys/ssh_key.pub

# Test SSH connection (FIXED: correct key name)
ssh -i /opt/proxmox-mcp/keys/ssh_key claude-user@localhost "whoami"

# Test from container (FIXED: correct path)
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml exec mcp-server ls -la /app/keys/
```

### Service Issues

**Problem: Container fails to start**
```bash
# Check Docker logs (note correct path)
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml logs mcp-server

# Check container status
sudo docker ps -a

# Restart services (systemd manages docker-compose)
sudo systemctl restart proxmox-mcp

# Manual container restart
cd /opt/proxmox-mcp/docker
sudo docker-compose -f docker-compose.prod.yml down
sudo docker-compose -f docker-compose.prod.yml up -d
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
# Verify MCP endpoint responds (FIXED: correct /api/mcp path)
curl -X POST http://YOUR_PROXMOX_IP:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'

# Use Claude CLI instead of manual config (FIXED: correct endpoint)
claude mcp remove proxmox-production  # if exists
claude mcp add --transport http proxmox-production http://YOUR_PROXMOX_IP:8080/api/mcp
claude mcp list  # verify connection

# Test tools in Claude Code
claude
# Try: "Please execute the command 'whoami'"
# Try: "Please list all VMs"
# Try: "Can you check if the pveproxy service is running?"
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
# Update system (FIXED: correct script path)
sudo ./scripts/install/install.sh

# Restart services
sudo systemctl restart proxmox-mcp

# View status
sudo systemctl status proxmox-mcp

# Run security validation
sudo -u claude-user ./comprehensive-security-validation.sh

# Check logs (FIXED: correct compose file path)
sudo journalctl -u proxmox-mcp --since today
cd /opt/proxmox-mcp/docker && sudo docker-compose -f docker-compose.prod.yml logs -f

# Test MCP functionality (FIXED: correct endpoint)
curl -f http://localhost:8080/health
claude mcp list
claude mcp add --transport http proxmox-production http://YOUR_PROXMOX_IP:8080/api/mcp

# Test practical admin permissions
sudo -u claude-user sudo systemctl status pveproxy
sudo -u claude-user sudo qm list
sudo -u claude-user sudo docker ps
sudo -u claude-user sudo docker images
```

---

---

## 🎯 CURRENT SYSTEM STATUS (v2.0 - Production Ready)

**✅ PHASE 1 COMPLETED - PRODUCTION READY:**

This system is now **production-ready** with all critical fixes applied:

### **✅ WHAT WORKS NOW:**

**Installation Process:**
```bash
# Single command installation from fresh Proxmox
cd ProxmoxMCP-Production && sudo ./scripts/install/install.sh
```

**Expected Outcome:**
- ✅ Docker container running and healthy
- ✅ SSH keys properly configured with 1000:1000 ownership
- ✅ MCP server responding on http://IP:8080/api/mcp (CORRECT ENDPOINT)
- ✅ execute_command tool validated and working
- ✅ All prerequisites installed (Docker, Node.js, etc.)
- ✅ Firewall configured for port 8080 access
- ✅ Client connection instructions with correct endpoint

**Client Connection:**
```bash
# Connect Claude Code to MCP server (FIXED ENDPOINT)
claude mcp add --transport http proxmox-production http://SERVER_IP:8080/api/mcp
claude mcp list  # Verify connection
```

**Available MCP Tools:**
- `execute_command(command, timeout)` - Run shell commands via SSH with practical admin permissions
- `list_vms()` - List all VMs via Proxmox API
- `vm_status(vmid, node)` - Get VM status
- `vm_action(vmid, node, action)` - Start/stop/restart VMs
- `node_status(node)` - Get Proxmox node information  
- `proxmox_api(method, path, data)` - Direct API calls

### **🔧 PRACTICAL ADMIN MODEL:**

**Philosophy**: "Enable real admin work, block only catastrophic operations"

**What You Can Do:**
- ✅ **Complete System Administration**: Install packages, manage services, configure system
- ✅ **Full VM/LXC Management**: Create, modify, start, stop, configure VMs and containers
- ✅ **Complete Docker Integration**: Pull images, create containers, map ports, manage volumes
- ✅ **Network Configuration**: Configure interfaces, firewall rules, routing
- ✅ **File System Operations**: Create, modify, backup, restore files and directories
- ✅ **Service Management**: Start, stop, restart, configure systemd services
- ✅ **Real Admin Tasks**: Package updates, log management, monitoring setup

**What's Protected:**
- ❌ **Cluster Destruction**: Can't destroy Proxmox cluster
- ❌ **Root Account Deletion**: Can't delete root user accounts
- ❌ **Storage Destruction**: Can't remove critical storage
- ❌ **Critical Infrastructure**: Can't stop core Proxmox services

### **🚀 DEMONSTRATED CAPABILITIES:**

**Docker Integration Example:**
```bash
# Through Claude Code MCP tools:
"Please show me all Docker images on the host"
"Pull the nginx:alpine image and create a new container"
"Map container port 80 to host port 8080 and start it"
"Show me the running containers and their port mappings"
```

**VM/LXC Management Example:**
```bash
# Through Claude Code MCP tools:
"List all VMs and their current status"
"Create a new Ubuntu 22.04 VM with 4GB RAM"
"Start VM 100 and show me its configuration"
"Create an LXC container with Docker pre-installed"
```

**System Administration Example:**
```bash
# Through Claude Code MCP tools:
"Check if the pveproxy service is running and restart it if needed"
"Install htop package using apt"
"Show me disk usage and clean up old log files"
"Configure ufw firewall to allow port 443"
```

---

**Installation Complete!** 

Your Proxmox MCP server is now ready for universal access from any Claude Code project with complete practical admin capabilities.