# 🚀 PROXMOX MCP INSTALLATION AUTOMATION GUIDE

**Enterprise-Grade Single-Command Installation System**

## 🎯 Overview

The Proxmox MCP Installation Automation provides a complete single-command installation experience that transforms the complex 20+ step manual process into a simple `./install.sh` command. This system leverages the existing excellent Docker infrastructure while incorporating comprehensive security and validation frameworks.

## 📋 Architecture Summary

### **Master Installation Script (`install.sh`)**
- **Single Entry Point**: `cd /opt/proxmox-mcp && ./install.sh`
- **Modular Design**: 6 distinct phases with individual validation
- **Error Handling**: Comprehensive rollback capabilities
- **Progress Tracking**: Real-time installation progress with detailed logging

### **Core Components**
1. **Configuration Management** (`install-config-manager.sh`)
2. **Update System** (`update-manager.sh`) 
3. **Validation Framework** (`validation-framework.sh`)
4. **Enhanced Security Integration** (existing bulletproof security model)

## 🔧 Installation Architecture

```
SINGLE COMMAND: ./install.sh
        ↓
┌─────────────────────────────────┐
│     PHASE 1: SYSTEM PREP       │ ← Prerequisites, Docker, Users
├─────────────────────────────────┤
│   PHASE 2: AUTO-DISCOVERY      │ ← Network scan, Configuration
├─────────────────────────────────┤
│   PHASE 3: SECURITY DEPLOY     │ ← Enhanced security, Validation
├─────────────────────────────────┤
│  PHASE 4: CONTAINER DEPLOY     │ ← Docker services, Health checks
├─────────────────────────────────┤
│   PHASE 5: CLIENT CONFIG       │ ← Claude Code, Universal access
├─────────────────────────────────┤
│   PHASE 6: FINAL VALIDATION    │ ← End-to-end testing
└─────────────────────────────────┘
        ↓
✅ UNIVERSAL ACCESS READY
```

## 📁 New File Structure

```
ProxmoxMCP-Production/
├── 🔧 install.sh                          # Master installation script
├── 🔧 install-config-manager.sh           # Configuration management
├── 🔧 update-manager.sh                   # Update system
├── 🔧 validation-framework.sh             # Validation testing
├── 📁 templates/                          # Configuration templates
│   ├── environment.template
│   ├── docker-compose.template
│   ├── Caddyfile.template
│   └── monitoring-services.template
├── 📁 schemas/                            # Validation schemas
│   └── config.schema.json
├── 📁 existing-files/                     # All existing excellent files
│   ├── docker/docker-compose.prod.yml    # Existing Docker excellence
│   ├── caddy/Caddyfile                    # Existing Caddy config
│   ├── claude-user-security-enhanced-sudoers # Existing security
│   └── comprehensive-security-validation.sh  # Existing validation
└── 📁 docs/
    └── INSTALLATION-AUTOMATION-GUIDE.md   # This guide
```

## 🚀 Single-Command Installation

### **Quick Start**
```bash
# Download and run installer
curl -L https://github.com/your-repo/ProxmoxMCP-Production/raw/main/install.sh | sudo bash

# Or clone and install
git clone https://github.com/your-repo/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production
sudo ./install.sh
```

### **Installation Process**

#### **Phase 1: System Preparation** (2-3 minutes)
```
🔍 Validating system requirements
🔧 Installing Docker and prerequisites  
👤 Setting up users and permissions
📁 Creating directory structure
```

#### **Phase 2: Auto-Discovery & Configuration** (1-2 minutes)
```
🔍 Scanning network for Proxmox servers
❓ Interactive configuration collection
🔑 SSH key generation and deployment
📝 Configuration file generation
✅ Configuration validation
```

#### **Phase 3: Security Deployment** (1 minute)
```
🔒 Deploying enhanced security configuration
🛡️  Running comprehensive security validation
📊 Setting up audit and monitoring
✅ Security compliance verification
```

#### **Phase 4: Container Deployment** (2-3 minutes)
```
📦 Pulling and building container images
🚀 Starting services with health checks
⚙️  Configuring systemd integration
🔄 Waiting for service readiness
✅ Service health verification
```

#### **Phase 5: Client Configuration** (1 minute)
```
📝 Generating Claude Code configuration
🔗 Testing MCP connection
🔧 Verifying tool availability
✅ Universal access configuration
```

#### **Phase 6: Final Validation** (1-2 minutes)
```
🔍 End-to-end connectivity testing
🧪 MCP tool functionality verification
📊 Performance and resource validation
📋 Installation report generation
```

### **Total Installation Time: 8-12 minutes**

## 🎮 User Experience Flow

### **1. Pre-Installation Check**
```bash
# Automatic system validation
✅ Operating System: Ubuntu 22.04 LTS
✅ Memory: 4GB available
✅ Disk Space: 25GB available
✅ Network: Connected
✅ Docker: Will be installed
```

### **2. Interactive Configuration**
```bash
=== PROXMOX MCP CONFIGURATION ===

Proxmox host (discovered: 192.168.1.137): [Enter]
SSH user for MCP operations [claude-user]: [Enter]  
SSH port [22]: [Enter]
Proxmox API user [root@pam]: [Enter]
Proxmox API token name [claude-mcp]: [Enter]

Please create the API token in Proxmox web interface:
1. Go to: https://192.168.1.137:8006
2. Navigate to: Datacenter → Permissions → API Tokens  
3. Add token: User=root@pam, Token ID=claude-mcp
4. Uncheck 'Privilege Separation' for full access

Enter the API token value: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

MCP server port [8080]: [Enter]
Enable monitoring dashboards? [y/N]: y
```

### **3. SSH Key Deployment**
```bash
=== SSH PUBLIC KEY DEPLOYMENT ===

Please add this public key to the Proxmox server:

ssh-copy-id -i /opt/proxmox-mcp/keys/claude_proxmox_key.pub claude-user@192.168.1.137

Or manually add to ~/.ssh/authorized_keys:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... proxmox-mcp-20231125-143022

Press Enter when SSH key is deployed...
```

### **4. Installation Progress**
```bash
============================================== 
PHASE: CONTAINER DEPLOYMENT
==============================================
Deploying Docker containers and services

Progress: [████████████████████] 100% - Service health verification
✅ Container images updated
✅ Services started successfully
✅ Health checks passed
✅ Monitoring dashboards activated
```

### **5. Success Summary**
```bash
==============================================
INSTALLATION COMPLETED SUCCESSFULLY!
==============================================

Service Status:
  Health: ✅ http://localhost:8080/health
  API Docs: ✅ http://localhost:8080/docs  
  MCP Endpoint: ✅ http://localhost:8080/api/mcp
  Grafana: ✅ http://localhost:3000 (admin/admin)
  Prometheus: ✅ http://localhost:9090

Next Steps:
  1. Add MCP server to Claude Code configuration
  2. Test connection: curl http://localhost:8080/health
  3. View installation report: cat /opt/proxmox-mcp/installation-report-*.md

🎉 Universal Proxmox MCP access is now available from any Claude Code project!
```

## 🔧 Configuration Management System

### **Auto-Discovery Engine**
```bash
# Network scanning for Proxmox servers
./install-config-manager.sh discover

🔍 Discovering network environment...
📍 Local IP: 192.168.1.100
📍 Network: 192.168.1.0/24
🔍 Scanning for Proxmox servers...
✅ Found Proxmox server: 192.168.1.137
✅ SSH accessible on 192.168.1.137

📊 Discovery Summary:
====================
IP Address      Version         SSH
----------------------------------------
192.168.1.137   pve-manager/7.4  ✅
```

### **Template-Based Configuration**
- **Environment Templates**: Dynamic `.env` generation
- **Docker Compose Templates**: Service-specific configurations  
- **Caddy Templates**: Network access patterns
- **Monitoring Templates**: Observability stack configuration

### **Multi-Environment Support**
```bash
# Environment-specific optimizations
./install-config-manager.sh optimize config.env production

✅ Applied production optimizations:
  - LOG_LEVEL=WARNING
  - SECURITY_LEVEL=maximum  
  - CPU_LIMIT=2.0
  - MEMORY_LIMIT=2G
```

## 🔄 Update Management System

### **Automated Update Detection**
```bash
# Check for updates
./update-manager.sh check

Current version: v1.0.0
Latest version: v1.1.0
⚠️  Update available: v1.0.0 → v1.1.0
```

### **Safe Update Process**
```bash
# Perform update with automatic rollback
./update-manager.sh update

🔄 Creating backup: update-backup-20231125-143022-v1.1.0
📦 Downloading update version: v1.1.0
🔧 Migrating configuration files
🔒 Updating security configuration
🚀 Performing rolling container updates
✅ Update completed successfully
```

### **Automated Update Scheduling**
```bash
# Setup automated weekly updates
./update-manager.sh setup-auto weekly

✅ Automated updates configured: weekly
⏰ Next update check: Sunday 02:00 AM
```

### **Rollback Capability**
```bash
# List available backups
./update-manager.sh list-backups

Backup ID                           Created             Size
----------------------------------------------------------------
update-backup-20231125-143022-v1.1.0  2023-11-25         245M
update-backup-20231120-091544-v1.0.0  2023-11-20         238M

# Rollback to previous version
./update-manager.sh rollback update-backup-20231125-143022-v1.1.0
```

## 🔍 Validation Framework

### **Multi-Level Validation**
```bash
# Comprehensive validation
./validation-framework.sh comprehensive

============================================== 
VALIDATION: COMPREHENSIVE
==============================================
Testing all system components and functionality

✅ System Requirements (5/5 tests passed)
✅ Network Environment (4/4 tests passed)  
✅ Installation Structure (8/8 tests passed)
✅ Configuration (6/6 tests passed)
✅ Services (7/7 tests passed)
✅ Connectivity (5/5 tests passed)
✅ Security (6/6 tests passed)
✅ MCP Tools (6/6 tools working)

🎉 ALL VALIDATION TESTS PASSED!
The Proxmox MCP installation is fully functional and ready for use.
```

### **Validation Levels**
- **Basic**: Quick system and structure validation
- **Standard**: Complete functional validation (default)
- **Comprehensive**: Full system validation including security and performance
- **Security**: Security-focused validation and compliance
- **Performance**: Performance and resource validation
- **Pre-Install**: Environment readiness validation
- **Post-Install**: Installation verification

### **Automated Health Monitoring**
```bash
# Setup continuous validation
./validation-framework.sh --report comprehensive

📊 Validation report generated: /var/log/proxmox-mcp-validation-reports/validation-report-20231125-143022.md

# View detailed report
cat /var/log/proxmox-mcp-validation-reports/validation-report-*.md
```

## 🔒 Security Integration

### **Enhanced Security Deployment**
The installation system seamlessly integrates with the existing bulletproof security model:

- **Automatic Security Configuration**: Deploys `claude-user-security-enhanced-sudoers`
- **Comprehensive Security Validation**: Runs `comprehensive-security-validation.sh`
- **Security Monitoring**: Sets up audit logging and monitoring
- **Compliance Verification**: Validates all security controls

### **Security Features Maintained**
- ✅ Root Protection Bypass - BULLETPROOF FIX
- ✅ Dangerous Command Coverage - ALL GAPS CLOSED
- ✅ Overly Permissive Patterns - MAXIMUM RESTRICTIONS  
- ✅ Environment Variable Manipulation - FULL PROTECTION
- ✅ Privilege Escalation Prevention - BULLETPROOF
- ✅ Command Bypass Prevention - MULTIPLE LAYERS

## 📊 Monitoring and Observability

### **Health Monitoring**
```bash
# Real-time health status
curl http://localhost:8080/health

{
  "status": "healthy",
  "timestamp": "2023-11-25T14:30:22Z",
  "checks": {
    "ssh_connectivity": "ok",
    "proxmox_api": "ok", 
    "mcp_tools": "ok",
    "security_config": "ok"
  },
  "server": "Proxmox MCP HTTP Server"
}
```

### **Monitoring Dashboards**
- **Grafana**: Application and system metrics at `http://localhost:3000`
- **Prometheus**: Metrics collection at `http://localhost:9090`
- **API Documentation**: Interactive docs at `http://localhost:8080/docs`

### **Log Management**
```bash
# Installation logs
tail -f /var/log/proxmox-mcp-install.log

# Validation logs  
tail -f /var/log/proxmox-mcp-validation.log

# Update logs
tail -f /var/log/proxmox-mcp-updates.log

# Security logs
tail -f /var/log/sudo-claude-user.log

# Application logs
docker-compose -f /opt/proxmox-mcp/docker-compose.yml logs -f
```

## 🚨 Troubleshooting

### **Installation Issues**

#### **Docker Installation Fails**
```bash
# Check system requirements
./validation-framework.sh pre-install

# Manual Docker installation
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER
```

#### **Network Discovery Fails**
```bash
# Manual configuration
./install.sh
# When prompted, enter Proxmox details manually
```

#### **SSH Connection Issues**
```bash
# Test SSH manually
ssh -i /opt/proxmox-mcp/keys/claude_proxmox_key claude-user@192.168.1.137

# Check SSH key permissions
ls -la /opt/proxmox-mcp/keys/
chmod 600 /opt/proxmox-mcp/keys/claude_proxmox_key
```

### **Service Issues**

#### **Containers Not Starting**
```bash
# Check Docker status
systemctl status docker

# Check container logs
cd /opt/proxmox-mcp
docker-compose logs

# Restart services
systemctl restart proxmox-mcp
```

#### **MCP Tools Not Working**
```bash
# Run targeted validation
./validation-framework.sh standard mcp_tools

# Check configuration
./validation-framework.sh standard configuration

# Test individual tool
curl -X POST http://localhost:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"1"}'
```

### **Security Issues**
```bash
# Run security validation
./validation-framework.sh security

# Check sudoers configuration
sudo visudo -c

# Verify user permissions
sudo -u claude-user sudo -l
```

### **Rollback Procedures**
```bash
# Emergency rollback
./install.sh rollback

# Restore from backup
./update-manager.sh rollback

# Manual recovery
cp -r /opt/proxmox-mcp-backups/latest/* /opt/proxmox-mcp/
systemctl restart proxmox-mcp
```

## 🎯 Advanced Usage

### **Custom Configuration**
```bash
# Use custom environment file
./install.sh --config /path/to/custom.env

# Skip interactive configuration
./install.sh --non-interactive --config-file config.env

# Development environment
./install.sh --environment development
```

### **Partial Installation**
```bash
# Run specific phases only
./install.sh --phases "system_preparation,configuration_discovery"

# Skip specific phases
./install.sh --skip-phases "security_deployment"
```

### **Enterprise Integration**
```bash
# Silent installation for automation
./install.sh --silent --config-file enterprise.env

# Integration with configuration management
ansible-playbook -i inventory proxmox-mcp-deploy.yml
```

## 📋 Command Reference

### **Installation Commands**
```bash
./install.sh                    # Complete installation
./install.sh rollback           # Emergency rollback
./install.sh validate           # Test current installation
```

### **Configuration Management**
```bash
./install-config-manager.sh discover                    # Network discovery
./install-config-manager.sh generate config.env        # Generate configuration
./install-config-manager.sh validate config.env        # Validate configuration  
./install-config-manager.sh optimize config.env prod   # Optimize for environment
```

### **Update Management**
```bash
./update-manager.sh check                    # Check for updates
./update-manager.sh update                   # Update to latest
./update-manager.sh update v1.2.0           # Update to specific version
./update-manager.sh rollback backup-id      # Rollback to backup
./update-manager.sh setup-auto weekly       # Setup automated updates
./update-manager.sh status                  # Show status
```

### **Validation Framework**
```bash
./validation-framework.sh                             # Standard validation
./validation-framework.sh comprehensive               # Full validation
./validation-framework.sh security                    # Security validation
./validation-framework.sh performance                 # Performance validation
./validation-framework.sh pre-install                 # Pre-installation check
./validation-framework.sh --report comprehensive      # Generate report
```

## 🎉 Benefits Achieved

### **User Experience**
- ✅ **Single Command**: `./install.sh` replaces 20+ manual steps
- ✅ **Auto-Discovery**: Automatic Proxmox server detection
- ✅ **Guided Setup**: Interactive configuration with validation
- ✅ **Progress Tracking**: Real-time installation progress
- ✅ **Error Recovery**: Comprehensive rollback capabilities

### **Reliability**
- ✅ **Idempotent**: Can be run multiple times safely
- ✅ **Validated**: Multi-layer validation at each phase
- ✅ **Self-Healing**: Automatic error detection and recovery
- ✅ **Monitored**: Continuous health and performance monitoring

### **Security**
- ✅ **Enhanced Security**: Full integration with bulletproof security model
- ✅ **Compliance**: Automated security validation and reporting
- ✅ **Audit Trail**: Comprehensive logging and monitoring
- ✅ **Best Practices**: Security-first architecture

### **Maintainability**
- ✅ **Automated Updates**: Safe, tested update mechanism
- ✅ **Configuration Management**: Template-based configuration
- ✅ **Monitoring**: Real-time health and performance dashboards
- ✅ **Documentation**: Comprehensive guides and troubleshooting

---

**🚀 The Proxmox MCP Installation Automation transforms a complex enterprise deployment into a simple, reliable, single-command experience while maintaining the highest standards of security, performance, and operational excellence.**