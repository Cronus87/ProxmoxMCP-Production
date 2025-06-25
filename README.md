# 🚀 Proxmox MCP Server - Production Deployment

**Universal Proxmox Management from Any Development Environment**

This repository contains a production-ready HTTP-based MCP (Model Context Protocol) server that provides complete Proxmox VE management capabilities accessible from any Claude Code project directory.

## 🎯 **What This Solves**

❌ **Before**: MCP server only works from specific directory  
✅ **After**: Universal access from any project, anywhere  

❌ **Before**: Manual deployment and management  
✅ **After**: Automated CI/CD with GitHub Actions  

❌ **Before**: Development-only setup  
✅ **After**: Production-ready with monitoring & security  

## 🏗️ **Architecture Overview**

```
Any Project Directory          Proxmox Server (Production)
┌─────────────────────┐       ┌─────────────────────────┐
│ Claude Code         │       │ Docker Stack            │
│ "type": "http"     │◄─────►│ ├─ MCP Server (FastAPI) │
│ "url": "http://..." │ HTTPS │ ├─ Caddy Reverse Proxy  │
│                     │       │ ├─ Prometheus Monitor   │
└─────────────────────┘       │ └─ Grafana Dashboard    │
                               └─────────────────────────┘
```

## ⚡ **Quick Start (5 Minutes)**

### **1. Clone & Setup Repository**
```bash
# Clone this repository
git clone https://github.com/YOUR-USERNAME/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production

# Configure environment
cp .env.example .env
vim .env  # Update with your Proxmox details
```

### **2. Configure GitHub Secrets**
In GitHub → Settings → Secrets and Variables → Actions, add:

```
PROXMOX_HOST=192.168.1.137
PROXMOX_USER=root  
PROXMOX_SSH_KEY=<your-ssh-private-key-content>
```

### **3. Deploy Automatically**
```bash
# Push to trigger automatic deployment
git add .
git commit -m "Initial deployment"
git push origin main

# GitHub Actions will automatically:
# ✅ Build Docker image
# ✅ Run security scans  
# ✅ Deploy to Proxmox
# ✅ Verify deployment
```

### **4. Configure Claude Code (Universal Access)**
Add to your global `~/.claude.json`:

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

### **5. Use From Anywhere! 🎉**
```bash
cd /any/project/directory
claude  # All Proxmox MCP tools available instantly!
```

## 🛠️ **Available MCP Tools**

Once deployed, you have access to these tools from any Claude Code session:

- **🔧 execute_command** - Run shell commands on Proxmox host
- **📋 list_vms** - List all VMs across nodes  
- **📊 vm_status** - Get detailed VM status
- **⚡ vm_action** - Start/stop/restart VMs
- **🖥️ node_status** - Get Proxmox node information
- **🔌 proxmox_api** - Direct Proxmox API calls

## 🔄 **CI/CD Pipeline Features**

### **Automated Workflows**
- **✅ On `main` push**: Deploy to production
- **✅ On `develop` push**: Deploy to staging  
- **✅ On `v*` tag**: Create versioned release
- **✅ On PR**: Run tests and validation

### **Security & Quality**
- **🛡️ Trivy security scanning** - Vulnerability detection
- **🧪 Automated testing** - pytest + linting
- **📋 SBOM generation** - Software bill of materials
- **🔐 Secret management** - GitHub Secrets integration

### **Production Features**
- **🚀 Zero-downtime deployments** - Blue-green strategy
- **📦 Container registry** - GitHub Container Registry
- **💾 Automatic backups** - Before each deployment
- **🔄 Rollback capability** - Quick failure recovery

## 📊 **Monitoring & Management**

### **Built-in Monitoring**
After deployment, access these endpoints:

- **Health Check**: `http://your-proxmox-ip/health`
- **API Documentation**: `http://your-proxmox-ip/docs`  
- **MCP Endpoint**: `http://your-proxmox-ip/api/mcp`
- **Grafana Dashboard**: `http://your-proxmox-ip:3000` (admin/admin)
- **Prometheus Metrics**: `http://your-proxmox-ip:9090`

### **Management Commands**
```bash
# View deployment status
gh workflow list

# Check application logs
ssh root@your-proxmox-ip 'cd /opt/proxmox-mcp && docker-compose logs -f'

# Restart service
ssh root@your-proxmox-ip 'systemctl restart proxmox-mcp'

# Update to latest
git tag v1.0.1 && git push origin v1.0.1  # Triggers deployment
```

## 🔧 **Configuration**

### **Environment Variables**
Configure in `.env` file:

```bash
# Container settings
IMAGE_TAG=latest
LOG_LEVEL=INFO

# SSH connection
SSH_HOST=192.168.1.137
SSH_USER=claude-user  
SSH_PORT=22

# Proxmox API
PROXMOX_HOST=192.168.1.137
PROXMOX_USER=root@pam
PROXMOX_TOKEN_NAME=claude-mcp
PROXMOX_TOKEN_VALUE=your-token-here

# Features
ENABLE_PROXMOX_API=true
ENABLE_DANGEROUS_COMMANDS=false
```

### **SSH Key Setup**
```bash
# Generate deployment key
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_deploy_key

# Copy to Proxmox
ssh-copy-id -i ~/.ssh/proxmox_deploy_key.pub root@192.168.1.137

# Add private key to GitHub Secrets
cat ~/.ssh/proxmox_deploy_key  # Copy to PROXMOX_SSH_KEY secret
```

## 🛡️ **Security Features**

### **Container Security**
- **Non-root execution** - mcpuser (UID 1000)
- **Minimal attack surface** - Python slim base image
- **Read-only volumes** - Configuration and keys
- **Resource limits** - CPU and memory constraints
- **Health checks** - Automated failure detection

### **Network Security**  
- **Reverse proxy** - Caddy with automatic HTTPS
- **Rate limiting** - Protection against abuse
- **CORS policies** - Controlled API access
- **Internal networking** - Container isolation

### **Operational Security**
- **Secret management** - Environment-based secrets
- **SSH key authentication** - No password access
- **Automated vulnerability scanning** - Trivy integration
- **Audit logging** - Container and application logs

## 🚨 **Troubleshooting**

### **Common Issues**

**❌ Deployment Fails**
```bash
# Check GitHub Actions
gh run list --limit 5
gh run view <run-id> --log

# Verify SSH access
ssh root@your-proxmox-ip 'docker ps'
```

**❌ MCP Connection Failed**
```bash
# Test health endpoint
curl http://your-proxmox-ip/health

# Check container logs
ssh root@your-proxmox-ip 'cd /opt/proxmox-mcp && docker-compose logs mcp-server'
```

**❌ Authentication Issues**
```bash
# Verify SSH keys
ssh root@your-proxmox-ip 'ls -la /opt/proxmox-mcp/keys/'

# Check environment
ssh root@your-proxmox-ip 'cd /opt/proxmox-mcp && cat .env'
```

### **Getting Help**

1. **📋 Check logs**: Application and deployment logs
2. **🔍 Verify endpoints**: Health and MCP API responses  
3. **🔧 Test connectivity**: SSH and HTTP access
4. **🎯 Review configuration**: Environment and secrets

## 📈 **Advanced Features**

### **Custom Domain Setup**
```bash
# 1. Update Caddyfile with your domain
vim caddy/Caddyfile  # Change to your-domain.com

# 2. Point DNS A record to Proxmox IP
# your-domain.com → 192.168.1.137

# 3. Update Claude Code config
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "https://your-domain.com/api/mcp"
    }
  }
}
```

### **High Availability**
```yaml
# Deploy multiple instances
services:
  mcp-server-1:
    # Primary instance
  mcp-server-2:  
    # Secondary instance
  haproxy:
    # Load balancer
```

### **Staging Environment**
```bash
# Create staging branch
git checkout -b develop
git push origin develop  # Auto-deploys to staging
```

## 🏆 **Success Indicators**

When everything is working correctly:

✅ **GitHub Actions pipeline** completes without errors  
✅ **Container images** build and push successfully  
✅ **Health endpoint** returns "healthy" status  
✅ **MCP tools** accessible from any project directory  
✅ **Monitoring dashboards** show green metrics  
✅ **Zero-downtime updates** work automatically  

## 📚 **Additional Resources**

- **[DevOps Guide](README-DEVOPS.md)** - Detailed CI/CD documentation
- **[Security Guide](SECURITY.md)** - Security best practices  
- **[API Documentation](http://your-proxmox-ip/docs)** - Interactive API docs
- **[Monitoring Guide](MONITORING.md)** - Grafana and Prometheus setup

---

**🚀 Built with**: FastMCP • FastAPI • Docker • GitHub Actions • Caddy • Prometheus • Grafana

**🎯 Result**: Universal Proxmox management from any development environment with enterprise-grade CI/CD!