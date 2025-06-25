# 📋 DEPLOYMENT INSTRUCTIONS

**Complete step-by-step guide to deploy your production Proxmox MCP server**

## 🚀 **Overview**

This guide will help you deploy a production-ready Proxmox MCP server that:
- ✅ **Works from any project directory** (universal access)
- ✅ **Deploys automatically** via GitHub Actions CI/CD
- ✅ **Updates automatically** when you push code changes
- ✅ **Includes monitoring** and health checks
- ✅ **Uses Docker containers** for reliable deployment

## 📁 **What's Included**

```
ProxmoxMCP-Production/
├── 📜 README.md                      # Main documentation
├── ⚡ QUICK-START.md                 # 5-minute setup guide
├── 📋 DEPLOYMENT-INSTRUCTIONS.md     # This file (detailed guide)
├── 🔧 .env.example                   # Configuration template
├── 🚫 .gitignore                     # Git ignore rules
├── 📊 VERSION                        # Version tracking
├── 🐍 run_mcp_server_http.py         # Main MCP server (FastAPI)
├── 📦 requirements-http.txt          # Python dependencies
├── 🏗️ .github/workflows/
│   └── build-and-deploy.yml         # CI/CD pipeline
├── 🐳 docker/
│   ├── Dockerfile.prod              # Production container image
│   └── docker-compose.prod.yml     # Multi-container deployment
├── 🚀 deploy/
│   └── deploy-production.sh         # Deployment automation script
├── 🔧 core/
│   ├── environment_manager.py       # Environment detection
│   └── proxmox_mcp_server.py       # Proxmox MCP implementation
├── 🌐 caddy/
│   └── Caddyfile                    # Reverse proxy configuration
└── 🔑 keys/
    └── .gitkeep                     # SSH keys directory
```

## 🎯 **Prerequisites Check**

Before starting, ensure you have:

### **✅ Development Environment**
- [ ] Git installed and configured
- [ ] GitHub CLI (`gh`) installed (optional but recommended)
- [ ] SSH client available
- [ ] Claude Code installed

### **✅ Proxmox Environment**
- [ ] Proxmox VE server running and accessible
- [ ] Root SSH access to Proxmox server
- [ ] Docker installed on Proxmox (or will be installed during setup)
- [ ] Network access from your development machine to Proxmox

### **✅ GitHub Account**
- [ ] GitHub account with repository access
- [ ] Ability to create repositories
- [ ] Access to repository settings (for secrets)

## 🔧 **Detailed Setup Process**

### **Step 1: Repository Preparation**

#### **Option A: Clone Existing Repository**
```bash
# If this is already a Git repository
git clone <repository-url>
cd ProxmoxMCP-Production
```

#### **Option B: Create New Repository**
```bash
# Create new repository on GitHub
gh repo create ProxmoxMCP-Production --public --clone
cd ProxmoxMCP-Production

# Copy all files from this directory to your repository
# (Use file manager or cp commands)
```

### **Step 2: Environment Configuration**

#### **Configure Application Settings**
```bash
# Copy the example environment file
cp .env.example .env

# Edit with your specific settings
vim .env  # or use your preferred editor
```

#### **Required Environment Variables**
Update these values in `.env`:

```bash
# === CRITICAL: Update these for your environment ===

# SSH Connection (for MCP server to connect to Proxmox)
SSH_HOST=192.168.1.137              # Your Proxmox IP address
SSH_USER=claude-user                # SSH user (create this user on Proxmox)
SSH_PORT=22                         # SSH port (usually 22)

# Proxmox API Connection
PROXMOX_HOST=192.168.1.137          # Same as SSH_HOST usually
PROXMOX_USER=root@pam               # Proxmox user with API access
PROXMOX_TOKEN_NAME=claude-mcp       # API token name (create in Proxmox)
PROXMOX_TOKEN_VALUE=your-token-here # API token value (from Proxmox)

# Features
ENABLE_PROXMOX_API=true             # Enable all MCP tools
ENABLE_DANGEROUS_COMMANDS=false     # Security: disable dangerous commands

# === Optional: Advanced settings ===
LOG_LEVEL=INFO                      # Logging level
IMAGE_TAG=latest                    # Container image tag
```

### **Step 3: Proxmox Server Preparation**

#### **Create MCP User on Proxmox**
```bash
# SSH to your Proxmox server
ssh root@192.168.1.137

# Create dedicated user for MCP operations
useradd -m -s /bin/bash claude-user
usermod -aG sudo claude-user  # Add sudo privileges

# Set password (or use SSH keys only)
passwd claude-user
```

#### **Create Proxmox API Token**
1. **Access Proxmox Web Interface**
   - Go to: `https://192.168.1.137:8006`
   - Login with root credentials

2. **Navigate to API Tokens**
   - Go to: `Datacenter` → `Permissions` → `API Tokens`

3. **Create New Token**
   - Click `Add`
   - User: `root@pam`
   - Token ID: `claude-mcp`
   - Comment: `Claude MCP Server Access`
   - Privilege Separation: `Unchecked` (for full access)

4. **Copy Token Value**
   - **IMPORTANT**: Copy the token value immediately
   - Update `PROXMOX_TOKEN_VALUE` in your `.env` file

#### **Install Docker on Proxmox (if not installed)**
```bash
# SSH to Proxmox server
ssh root@192.168.1.137

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Add users to docker group
usermod -aG docker root
usermod -aG docker claude-user

# Test installation
docker --version
docker-compose --version
```

### **Step 4: SSH Key Setup**

#### **Generate Deployment SSH Key**
```bash
# On your development machine
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_deploy_key -C "proxmox-mcp-deployment"

# This creates:
# ~/.ssh/proxmox_deploy_key      (private key)
# ~/.ssh/proxmox_deploy_key.pub  (public key)
```

#### **Deploy Public Key to Proxmox**
```bash
# Copy public key to root user (for deployment)
ssh-copy-id -i ~/.ssh/proxmox_deploy_key.pub root@192.168.1.137

# Copy public key to MCP user (for operations)
ssh-copy-id -i ~/.ssh/proxmox_deploy_key.pub claude-user@192.168.1.137

# Test SSH access
ssh -i ~/.ssh/proxmox_deploy_key root@192.168.1.137 "echo 'Deployment SSH OK'"
ssh -i ~/.ssh/proxmox_deploy_key claude-user@192.168.1.137 "echo 'Operations SSH OK'"
```

#### **Copy SSH Key for MCP Server**
```bash
# Copy the SSH key to the keys directory for the MCP server to use
cp ~/.ssh/proxmox_deploy_key keys/claude_proxmox_key
cp ~/.ssh/proxmox_deploy_key.pub keys/claude_proxmox_key.pub

# Secure the private key
chmod 600 keys/claude_proxmox_key
```

### **Step 5: GitHub Configuration**

#### **Create GitHub Repository (if not done)**
```bash
# Using GitHub CLI
gh repo create ProxmoxMCP-Production --public

# Or create manually on GitHub web interface
```

#### **Configure GitHub Secrets**
Go to your GitHub repository:
1. **Settings** → **Secrets and Variables** → **Actions**
2. **New repository secret** for each of these:

```
Secret Name: PROXMOX_HOST
Secret Value: 192.168.1.137

Secret Name: PROXMOX_USER
Secret Value: root

Secret Name: PROXMOX_SSH_KEY
Secret Value: [paste entire content of ~/.ssh/proxmox_deploy_key]
```

**To get SSH private key content:**
```bash
cat ~/.ssh/proxmox_deploy_key
# Copy everything including -----BEGIN OPENSSH PRIVATE KEY----- and -----END OPENSSH PRIVATE KEY-----
```

### **Step 6: Initial Deployment**

#### **Commit and Push Code**
```bash
# Add all files to Git
git add .

# Commit with descriptive message
git commit -m "Initial deployment: Production Proxmox MCP Server

- FastAPI-based HTTP MCP server
- Docker containerization with Caddy reverse proxy
- GitHub Actions CI/CD pipeline
- Prometheus monitoring and Grafana dashboards
- SSH key authentication and API token access
- Universal access from any Claude Code project"

# Push to trigger deployment
git push origin main
```

#### **Monitor Deployment**
```bash
# Using GitHub CLI
gh run list
gh run view <run-id> --log

# Or watch in GitHub web interface
# Go to your repository → Actions tab
```

#### **Verify Deployment Success**
```bash
# Test health endpoint
curl http://192.168.1.137/health

# Expected response:
# {"status":"healthy","checks":{...},"server":"Proxmox MCP HTTP Server"}

# Test MCP endpoint
curl http://192.168.1.137/api/mcp

# Test API documentation
curl http://192.168.1.137/docs
```

### **Step 7: Claude Code Configuration**

#### **Global Configuration (Recommended)**
```bash
# Edit global Claude Code configuration
vim ~/.claude.json

# Add or merge this configuration:
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "http://192.168.1.137/api/mcp",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    }
  }
}
```

#### **Using Claude CLI (Alternative)**
```bash
claude mcp add proxmox-mcp --transport http --url http://192.168.1.137/api/mcp
```

#### **Project-Specific Configuration (Optional)**
```bash
# For project-specific access, add to project's .claude.json
cd /your/project/directory
vim .claude.json

# Add same MCP server configuration
```

### **Step 8: Testing and Validation**

#### **Test Universal Access**
```bash
# Test from multiple project directories
cd /tmp && claude --debug | grep -i proxmox
cd /home/user/project1 && claude --debug | grep -i proxmox
cd /home/user/project2 && claude --debug | grep -i proxmox

# All should show successful MCP connection
```

#### **Test MCP Tools**
Open Claude Code from any directory and test:

```
# Example prompts to test:
"List all VMs on my Proxmox server"
"Show the status of VM 100"
"Execute 'uptime' command on the Proxmox host"
"Get the status of the Proxmox node"
"Show me the Proxmox API version"
```

#### **Expected MCP Tools Available**
- ✅ `execute_command` - Execute shell commands
- ✅ `list_vms` - List all virtual machines
- ✅ `vm_status` - Get VM status and details
- ✅ `vm_action` - Start, stop, restart VMs
- ✅ `node_status` - Get Proxmox node information
- ✅ `proxmox_api` - Direct Proxmox API calls

## 📊 **Post-Deployment Monitoring**

### **Access Monitoring Dashboards**
- **Health Check**: `http://192.168.1.137/health`
- **API Documentation**: `http://192.168.1.137/docs`
- **Grafana Dashboard**: `http://192.168.1.137:3000` (admin/admin)
- **Prometheus Metrics**: `http://192.168.1.137:9090`

### **Log Monitoring**
```bash
# Application logs
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && docker-compose logs -f mcp-server'

# System service logs
ssh root@192.168.1.137 'journalctl -u proxmox-mcp -f'

# Container status
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && docker-compose ps'
```

## 🔄 **Ongoing Operations**

### **Making Updates**
```bash
# Edit code
vim run_mcp_server_http.py

# Commit and push - triggers automatic deployment
git add .
git commit -m "Add new MCP tool functionality"
git push origin main
```

### **Version Releases**
```bash
# Create tagged release
git tag v1.0.1 -m "Release v1.0.1: Enhanced VM management"
git push origin v1.0.1

# Triggers production deployment with specific version
```

### **Managing Service**
```bash
# Restart service
ssh root@192.168.1.137 'systemctl restart proxmox-mcp'

# Check status
ssh root@192.168.1.137 'systemctl status proxmox-mcp'

# Update containers
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && docker-compose pull && docker-compose up -d'
```

## 🚨 **Troubleshooting Guide**

### **Deployment Issues**

**❌ GitHub Actions Fails**
```bash
# Check workflow logs
gh run list --limit 5
gh run view <failed-run-id> --log

# Common issues:
# - Missing GitHub secrets
# - SSH connection problems
# - Docker installation issues
```

**❌ SSH Connection Problems**
```bash
# Test SSH manually
ssh -i ~/.ssh/proxmox_deploy_key root@192.168.1.137

# Check SSH key permissions
ls -la ~/.ssh/proxmox_deploy_key  # Should be 600

# Verify public key is on Proxmox
ssh root@192.168.1.137 'cat ~/.ssh/authorized_keys'
```

**❌ Docker Issues on Proxmox**
```bash
# Check Docker installation
ssh root@192.168.1.137 'docker --version'
ssh root@192.168.1.137 'docker-compose --version'

# Check Docker service
ssh root@192.168.1.137 'systemctl status docker'

# Restart Docker if needed
ssh root@192.168.1.137 'systemctl restart docker'
```

### **Runtime Issues**

**❌ MCP Server Not Responding**
```bash
# Check container status
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && docker-compose ps'

# Check container logs
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && docker-compose logs mcp-server'

# Restart containers
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && docker-compose restart'
```

**❌ Authentication Failures**
```bash
# Check SSH key in container
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && ls -la keys/'

# Check API token
ssh root@192.168.1.137 'cd /opt/proxmox-mcp && cat .env | grep TOKEN'

# Test Proxmox API manually
curl -k "https://192.168.1.137:8006/api2/json/version" \
  -H "Authorization: PVEAPIToken=root@pam!claude-mcp=your-token-value"
```

**❌ Claude Code Connection Issues**
```bash
# Test health endpoint
curl http://192.168.1.137/health

# Test MCP endpoint
curl -X POST http://192.168.1.137/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"1"}'

# Check Claude Code configuration
cat ~/.claude.json | grep -A 10 proxmox-mcp
```

## 🎯 **Success Validation**

Your deployment is successful when:

✅ **GitHub Actions pipeline** completes without errors  
✅ **Health endpoint** returns `{"status": "healthy"}`  
✅ **MCP endpoint** responds to tool list requests  
✅ **Claude Code** connects without failed status  
✅ **All 6 MCP tools** are available in any project  
✅ **Monitoring dashboards** are accessible  
✅ **Automatic updates** work via git push  

## 📞 **Getting Help**

If you encounter issues:

1. **📋 Check logs** - Application and deployment logs
2. **🔍 Verify endpoints** - Health and MCP API responses
3. **🔧 Test connectivity** - SSH and HTTP access
4. **⚙️ Review configuration** - Environment variables and secrets
5. **🔄 Try manual deployment** - Use deployment script directly

---

**🎉 Congratulations!** You now have a production-ready, universally accessible Proxmox MCP server with automated CI/CD deployment!