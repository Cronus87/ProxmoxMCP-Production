# Proxmox MCP - Quick Start Guide

**Get Proxmox management in Claude Code in under 10 minutes**

## TL;DR - Fast Track Installation

```bash
# 1. Run single-command installer
curl -fsSL https://raw.githubusercontent.com/YOUR-REPO/ProxmoxMCP-Production/main/install.sh | sudo bash

# 2. Add to ~/.claude.json
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "http://YOUR_PROXMOX_IP:8080/api/mcp"
    }
  }
}

# 3. Use from anywhere!
cd /any/project && claude
```

---

## Prerequisites (2 minutes)

### Required Information
- **Proxmox IP address** (e.g., 192.168.1.137)
- **Root access** to Proxmox server
- **Network connectivity** between client and Proxmox

### Quick Verification
```bash
# Test Proxmox connectivity
ping YOUR_PROXMOX_IP

# Test SSH access (should prompt for password)
ssh root@YOUR_PROXMOX_IP "echo 'Connected'"
```

---

## Installation (5 minutes)

### Method 1: Automated Installation (Recommended)

```bash
# Download and run installer
wget https://raw.githubusercontent.com/YOUR-REPO/ProxmoxMCP-Production/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

**Installation will prompt for:**
- Proxmox host IP (auto-detected if possible)
- SSH user (defaults to claude-user)
- API token name (defaults to claude-mcp)
- API token value (create in Proxmox web interface)

### Method 2: Git Clone Installation

```bash
git clone https://github.com/YOUR-REPO/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production
sudo ./install.sh
```

### During Installation

**When prompted for API token:**

1. Open Proxmox web interface: `https://YOUR_PROXMOX_IP:8006`
2. Navigate to: **Datacenter → Permissions → API Tokens**
3. Click **Add**, set:
   - User: `root@pam`
   - Token ID: `claude-mcp`
   - **Uncheck** "Privilege Separation"
4. Copy the generated token value
5. Paste into installer prompt

**SSH Key Deployment:**
The installer will display a command like:
```bash
ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key.pub claude-user@YOUR_PROXMOX_IP
```
Run this command and enter the root password when prompted.

---

## Claude Code Configuration (1 minute)

### Universal Access (Recommended)

Add to your global `~/.claude.json`:

```json
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "http://YOUR_PROXMOX_IP:8080/api/mcp",
      "headers": {
        "Content-Type": "application/json"
      }
    }
  }
}
```

### Verify Configuration

```bash
# Start Claude Code from any directory
cd /any/project/directory
claude

# Check if MCP tools are available - you should see:
# - mcp__proxmox-production__execute_command
# - mcp__proxmox-production__list_vms
# - mcp__proxmox-production__vm_status
# - mcp__proxmox-production__vm_action
# - mcp__proxmox-production__node_status
# - mcp__proxmox-production__proxmox_api
```

---

## Verification (2 minutes)

### Health Check

```bash
# Test service health
curl http://YOUR_PROXMOX_IP:8080/health

# Expected response:
# {"status": "healthy", "timestamp": "...", "version": "1.0.0"}
```

### MCP API Test

```bash
# Test MCP endpoint
curl -X POST http://YOUR_PROXMOX_IP:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'

# Should return list of available tools
```

### Quick Functionality Test

From Claude Code in any project directory:

```
User: List all VMs on my Proxmox server
Claude: I'll list all VMs on your Proxmox server using the MCP tools.
[Should show VM list from your Proxmox]
```

---

## Common Quick Fixes

### Issue: Health check fails
```bash
# Check if service is running
sudo systemctl status proxmox-mcp

# Restart if needed
sudo systemctl restart proxmox-mcp
```

### Issue: MCP tools not available in Claude Code
```bash
# Verify ~/.claude.json exists and has correct format
cat ~/.claude.json

# Test MCP endpoint directly
curl http://YOUR_PROXMOX_IP:8080/api/mcp -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"tools/list","id":"1"}'
```

### Issue: SSH authentication fails
```bash
# Test SSH key
ssh -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@YOUR_PROXMOX_IP "whoami"

# Re-deploy key if needed
ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key.pub claude-user@YOUR_PROXMOX_IP
```

### Issue: API authentication fails
```bash
# Test API token
curl -k -H "Authorization: PVEAPIToken=root@pam!claude-mcp=YOUR_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version

# If fails, regenerate token in Proxmox web interface
```

---

## Next Steps

### Explore Available Tools

In Claude Code, you can now:

```
# VM Management
"Start VM 101"
"Show status of all VMs"
"Stop VM named 'web-server'"

# System Information  
"Show Proxmox node status"
"List running containers"
"Check system resources"

# Direct Commands
"Run 'df -h' on Proxmox server"
"Check network interfaces"
"Show active services"
```

### Enable Monitoring (Optional)

```bash
# Add monitoring to installation
echo "ENABLE_MONITORING=y" | sudo tee -a /opt/proxmox-mcp/.env
sudo systemctl restart proxmox-mcp

# Access dashboards:
# Grafana: http://YOUR_PROXMOX_IP:3000 (admin/admin)
# Prometheus: http://YOUR_PROXMOX_IP:9090
```

### HTTPS/External Access (Optional)

```bash
# Update Caddy configuration for external domain
sudo nano /opt/proxmox-mcp/caddy/Caddyfile

# Change localhost to your domain
# Point DNS A record to Proxmox IP
# Restart services
sudo systemctl restart proxmox-mcp
```

---

## Success Checklist

✅ **Installation completed** without errors  
✅ **Health endpoint** responds: `curl http://YOUR_PROXMOX_IP:8080/health`  
✅ **MCP tools** visible in Claude Code  
✅ **VM listing** works from Claude Code  
✅ **Command execution** works via SSH  
✅ **Proxmox API** accessible with token  

## Support

**Complete Documentation:**
- **Full Installation Guide**: `docs/INSTALLATION-GUIDE.md`
- **Troubleshooting Guide**: `docs/TROUBLESHOOTING-GUIDE.md`
- **Security Guide**: `docs/SECURITY-GUIDE.md`
- **Administrator Guide**: `docs/ADMINISTRATOR-GUIDE.md`

**Quick Help:**
```bash
# View installation log
sudo tail -f /var/log/proxmox-mcp-install.log

# Check service status
sudo systemctl status proxmox-mcp

# View container logs
sudo docker logs proxmox-mcp-server

# Run security validation
sudo -u claude-user ./comprehensive-security-validation.sh
```

**Health Endpoints:**
- **Service Health**: `http://YOUR_PROXMOX_IP:8080/health`
- **API Documentation**: `http://YOUR_PROXMOX_IP:8080/docs`
- **Installation Report**: `/opt/proxmox-mcp/installation-report-[ID].md`

---

**🎉 Congratulations!** 

You now have universal Proxmox management access from any Claude Code project!