# 🚀 QUICK START GUIDE - Proxmox MCP Production Deployment

**Get your universal Proxmox MCP server running in 5 minutes!**

## ⚡ **Prerequisites**

- ✅ **GitHub account** (for repository and CI/CD)
- ✅ **Proxmox server** running and accessible
- ✅ **SSH access** to Proxmox with root privileges
- ✅ **Claude Code** installed on your development machine

## 🎯 **Step 1: Repository Setup**

### **Option A: Use This Repository**
```bash
# Clone this repository
git clone <this-repo-url>
cd ProxmoxMCP-Production

# Or download as ZIP and extract
```

### **Option B: Create New Repository**
```bash
# Create new repository on GitHub
gh repo create ProxmoxMCP-Production --public
git clone https://github.com/YOUR-USERNAME/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production

# Copy all files from this folder to your new repository
```

## 🔧 **Step 2: Configure Environment**

### **Update Configuration**
```bash
# Copy example environment file
cp .env.example .env

# Edit with your Proxmox details
vim .env
```

**Required changes in `.env`:**
```bash
# Update these values for your environment
SSH_HOST=192.168.1.137          # Your Proxmox IP
SSH_USER=claude-user            # Your SSH user (not root!)
PROXMOX_HOST=192.168.1.137      # Your Proxmox IP
PROXMOX_TOKEN_VALUE=your-token  # Your Proxmox API token
```

### **Create Proxmox API Token**
1. **Login to Proxmox web interface** (https://your-proxmox-ip:8006)
2. **Go to**: Datacenter → Permissions → API Tokens
3. **Add new token**: User: `root@pam`, Token ID: `claude-mcp`
4. **Copy the token value** and update `.env` file

## 🔐 **Step 3: SSH Key Setup**

### **Generate SSH Key for Deployment**
```bash
# Generate deployment key
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_deploy_key -C "github-actions-deploy"

# Copy public key to Proxmox
ssh-copy-id -i ~/.ssh/proxmox_deploy_key.pub root@192.168.1.137

# Test SSH connection
ssh -i ~/.ssh/proxmox_deploy_key root@192.168.1.137 "echo 'SSH OK'"
```

### **Setup SSH Key for Your User**
```bash
# Copy the key for your MCP user too (claude-user)
ssh-copy-id -i ~/.ssh/proxmox_deploy_key.pub claude-user@192.168.1.137

# Or manually add to authorized_keys if user doesn't exist yet
```

## ⚙️ **Step 4: GitHub Configuration**

### **Add GitHub Secrets**
Go to your GitHub repository → **Settings** → **Secrets and Variables** → **Actions**

Add these secrets:
```
Name: PROXMOX_HOST
Value: 192.168.1.137

Name: PROXMOX_USER  
Value: root

Name: PROXMOX_SSH_KEY
Value: [paste content of ~/.ssh/proxmox_deploy_key file]
```

**To get SSH key content:**
```bash
cat ~/.ssh/proxmox_deploy_key
# Copy the entire output (including BEGIN/END lines)
```

## 🚀 **Step 5: Deploy**

### **Initial Deployment**
```bash
# Commit and push to trigger deployment
git add .
git commit -m "Initial deployment: Proxmox MCP Server"
git push origin main
```

### **Monitor Deployment**
```bash
# Watch GitHub Actions
gh run list
gh run view <run-id> --log

# Or check in GitHub web interface
# Go to Actions tab in your repository
```

### **Verify Deployment**
```bash
# Test health endpoint (replace with your IP)
curl http://192.168.1.137/health

# Should return: {"status": "healthy", ...}
```

## 🎮 **Step 6: Configure Claude Code**

### **Add to Global Configuration**
Edit `~/.claude.json` (create if doesn't exist):

```json
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "http://192.168.1.137/api/mcp"
    }
  }
}
```

**Or use Claude CLI:**
```bash
claude mcp add proxmox-mcp --transport http --url http://192.168.1.137/api/mcp
```

## ✅ **Step 7: Test Universal Access**

### **Test from Any Project**
```bash
# Go to any project directory
cd /any/project/directory

# Start Claude Code
claude

# In Claude Code, try:
# "List all VMs on my Proxmox server"
# "Show the status of VM 100"
# "Execute 'df -h' on the Proxmox host"
```

### **Verify All Tools Work**
The following MCP tools should be available:
- ✅ **execute_command** - Run shell commands
- ✅ **list_vms** - List all VMs
- ✅ **vm_status** - Get VM status
- ✅ **vm_action** - Start/stop VMs
- ✅ **node_status** - Get node info
- ✅ **proxmox_api** - Direct API calls

## 🎉 **Success!**

You now have:
- ✅ **Universal MCP access** from any project directory
- ✅ **Automated CI/CD** - updates deploy automatically
- ✅ **Production monitoring** at `http://your-ip/health`
- ✅ **API documentation** at `http://your-ip/docs`
- ✅ **Container-based deployment** with Docker

## 🚨 **Troubleshooting**

### **Common Issues**

**❌ "Connection refused"**
```bash
# Check if deployment completed
ssh root@192.168.1.137 'systemctl status proxmox-mcp'

# Check container status
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && docker-compose ps'
```

**❌ "Authentication failed"**
```bash
# Verify SSH key setup
ssh -i ~/.ssh/proxmox_deploy_key root@192.168.1.137 'whoami'

# Check if keys are copied to deployment
ssh root@192.168.1.137 'ls -la /opt/proxmox-mcp/keys/'
```

**❌ "MCP tools not found"**
```bash
# Test MCP endpoint directly
curl -X POST http://192.168.1.137/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"1"}'
```

### **Get Help**
- **📋 Check deployment logs**: `gh run view <run-id> --log`
- **🔍 Check application logs**: `ssh root@your-ip 'cd /opt/proxmox-mcp && docker-compose logs'`
- **🏥 Check health status**: `curl http://your-ip/health`

## 🔄 **Making Updates**

### **Update Code**
```bash
# Make changes to code
vim run_mcp_server_http.py

# Commit and push - automatically deploys!
git add .
git commit -m "Updated MCP server functionality"
git push origin main
```

### **Version Releases**
```bash
# Create tagged release
git tag v1.0.1
git push origin v1.0.1

# Triggers production deployment with version v1.0.1
```

---

**🎯 That's it!** You now have a production-ready, universally accessible Proxmox MCP server with automated CI/CD!