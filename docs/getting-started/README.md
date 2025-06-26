# Getting Started with Proxmox MCP

Welcome! This section will get you from zero to a working Proxmox MCP installation quickly and efficiently.

## 🎯 Choose Your Path

| I want to... | Start Here | Time Needed |
|--------------|------------|-------------|
| **Quick demo** | [Quick Start](quick-start.md) | 10 minutes |
| **Production deployment** | [Installation Guide](installation.md) | 30 minutes |
| **Understand the system** | [Architecture Overview](#architecture-overview) | 15 minutes |

## 📋 Prerequisites

Before starting, ensure you have:
- ✅ **Proxmox VE system** (version 7.0+ recommended)
- ✅ **Root access** to the Proxmox server
- ✅ **Internet connectivity** for package downloads
- ✅ **2GB RAM and 10GB disk space** available
- ✅ **Claude Code installed** on your client machine

## 🚀 Quick Start Path

Perfect for trying out Proxmox MCP or development environments:

### Step 1: Quick Installation
```bash
# Clone and install in one command
git clone https://github.com/YOUR-ORG/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production
sudo ./scripts/install/install.sh
```

### Step 2: Connect Claude Code
```bash
# Add MCP server (replace with your server IP)
claude mcp add --transport http proxmox-production http://YOUR_IP:8080/api/mcp

# Verify connection
claude mcp list
```

### Step 3: Test Functionality
Use Claude Code in any project to manage your Proxmox system!

**→ Continue to:** [Quick Start Guide](quick-start.md)

## 🏢 Production Deployment Path

For enterprise environments requiring security validation and documentation:

### Step 1: Security Review
- Review [Security Architecture](../security/security-guide.md)
- Understand [Security Controls](../security/enhanced-sudoers.md)
- Plan [Compliance Requirements](../security/compliance.md)

### Step 2: Production Installation
- Follow [Complete Installation Guide](installation.md)
- Configure [Enterprise Security](../security/best-practices.md)
- Set up [Monitoring and Alerting](../administration/README.md)

### Step 3: Team Onboarding
- Train administrators on [Daily Operations](../administration/daily-operations.md)
- Set up [Integration Procedures](../integration/README.md)
- Establish [Maintenance Procedures](../administration/README.md)

**→ Continue to:** [Installation Guide](installation.md)

## 🏗️ Architecture Overview

Understanding the Proxmox MCP architecture helps with planning and troubleshooting:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Claude Code   │◄──►│  Proxmox MCP    │◄──►│   Proxmox VE    │
│                 │    │     Server      │    │                 │
│  • Projects     │    │  • Docker       │    │  • VMs/LXCs     │
│  • Commands     │    │  • Security     │    │  • Storage      │
│  • Integration  │    │  • Monitoring   │    │  • Network      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
       │                        │                        │
       │                        │                        │
   HTTP/MCP                 SSH + API              Management API
   Port 8080              claude-user               root@pam token
```

### Key Components

**🐳 Docker Container**
- FastMCP-based HTTP server
- Security-hardened environment
- Resource-controlled execution
- Health monitoring and auto-restart

**🔐 Security Layer**
- 85+ security controls
- Restricted claude-user permissions
- Command filtering and validation
- Complete audit logging

**🔌 API Integration**
- Proxmox VE API access
- SSH command execution
- Real-time VM/container management
- Storage and network operations

### Data Flow

1. **Claude Code** sends MCP requests to container
2. **MCP Server** validates and routes requests
3. **Security Layer** filters and approves commands
4. **Execution Layer** runs commands via SSH or API
5. **Results** flow back through the same secure path

## 📚 Documentation Overview

This getting-started section includes:

### [Quick Start Guide](quick-start.md)
**Best for:** First-time users, demos, development
- Single-command installation
- Basic Claude Code setup
- Immediate functionality testing
- **Time:** 10 minutes

### [Installation Guide](installation.md)
**Best for:** Production deployments, enterprise use
- Comprehensive installation process
- Security configuration and validation
- Production deployment considerations
- Enterprise integration setup
- **Time:** 30-45 minutes

## 🔄 Next Steps

After completing your installation:

### Immediate Next Steps
1. **Verify Installation**: Run through [Quick Start](quick-start.md) validation
2. **Security Review**: Check [Security Guide](../security/security-guide.md)
3. **Basic Operations**: Learn [Daily Operations](../administration/daily-operations.md)

### Advanced Configuration
1. **Enterprise Integration**: Set up [SSO and RBAC](../integration/README.md)
2. **Monitoring**: Configure [Health Monitoring](../administration/README.md)
3. **Backup Strategy**: Plan [Backup and Recovery](../administration/README.md)

### Team Enablement
1. **User Training**: Share [Integration Guide](../integration/README.md)
2. **Administrator Training**: Review [Administration Guide](../administration/README.md)
3. **Developer Onboarding**: Use [API Reference](../reference/README.md)

## 🆘 Getting Help

If you encounter issues during setup:

### Quick Fixes
- **Installation Problems**: Check [Troubleshooting](../administration/troubleshooting.md)
- **Connection Issues**: Review [Integration Guide](../integration/claude-code-setup.md)
- **Permission Errors**: See [Security Guide](../security/security-guide.md)

### Support Channels
- **Documentation**: Search these guides first
- **Issues**: Report bugs on GitHub Issues
- **Discussions**: Ask questions in GitHub Discussions
- **Security**: Email security@your-domain.com for security issues

---

**🎉 Ready to start?** Choose your path above and begin your Proxmox MCP journey!