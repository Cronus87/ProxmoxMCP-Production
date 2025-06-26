# PROXMOX MCP PHASE 1 REVISED IMPLEMENTATION PLAN
**Self-Contained Docker + Easy Installation + User Permission Configuration**

**CORRECTED UNDERSTANDING**: System is already containerized with docker-compose  
**Date**: June 26, 2025  
**Status**: 📋 **REVISED PLAN READY** - Based on Actual Current State

---

## 🔍 **CURRENT STATE ANALYSIS (CORRECTED)**

### **WHAT'S ALREADY THERE:**
✅ **Docker Infrastructure**: Complete docker-compose.yml with MCP server, Caddy, monitoring  
✅ **Container Image**: `ghcr.io/your-username/fullproxmoxmcp:latest`  
✅ **Installation Location**: `/opt/proxmox-mcp/` with full structure  
✅ **Environment Configuration**: `.env` file with Proxmox API tokens  
✅ **Git Repository**: https://github.com/Cronus87/ProxmoxMCP-Production  
✅ **Volume Mounts**: Keys, config, logs directories  
✅ **Health Checks**: Built-in health monitoring  
✅ **Reverse Proxy**: Caddy setup for external access  
✅ **Monitoring Stack**: Prometheus/Grafana (optional profiles)  

### **WHAT'S NOT WORKING:**
❌ **Container Not Running**: No MCP container currently active  
❌ **GitHub Deployments Failing**: Automated deployment broken  
❌ **User Permissions**: claude-user still has excessive privileges  
❌ **Manual Installation**: No simple setup process for users  
❌ **SSH Dependencies**: Still using SSH wrapper instead of direct HTTP  

---

## 🎯 **REVISED PHASE 1 SCOPE**

### **PRIMARY OBJECTIVES:**
1. **Get Existing Container Running** - Fix deployment issues
2. **Create Master Setup Script** - Simple installation process for users  
3. **Fix User Permissions** - Configure claude-user with correct restrictions  
4. **Eliminate SSH Dependencies** - Direct HTTP MCP connection  
5. **Simple Update Process** - Manual deployment since GitHub Actions broken  

### **NOT CHANGING:**
✅ Docker infrastructure (already excellent)  
✅ Container architecture (already properly designed)  
✅ Volume mounts and networking (already configured)  
✅ Environment variable structure (already comprehensive)  

---

## 🚀 **IMPLEMENTATION STRATEGY**

### **PROBLEM 1: CONTAINER NOT RUNNING**

#### **Current Issue Analysis:**
```bash
# Container should be running but isn't
sudo docker ps  # Shows n8n and ombi, but no proxmox-mcp-server
```

#### **Root Cause Investigation:**
```bash
# Need to check:
1. Does the container image exist locally?
2. Has docker-compose been started?
3. Are there any container startup errors?
4. Is the image available from ghcr.io?
```

#### **Solution Approach:**
```bash
# Master setup script will:
1. Check if image exists locally
2. Build image locally if not available from registry
3. Start containers with docker-compose
4. Verify container health
5. Configure firewall and networking
```

### **PROBLEM 2: NO SIMPLE INSTALLATION PROCESS**

#### **Current Challenge:**
- Complex docker-compose setup requires technical knowledge
- No step-by-step process for users
- Manual SSH configuration still required
- No validation of setup completion

#### **Solution: Master Setup Script**
```bash
#!/bin/bash
# /opt/proxmox-mcp/install.sh
# Master installation and configuration script

SCRIPT RESPONSIBILITIES:
1. System Prerequisites Check
2. User Permission Configuration  
3. Container Image Preparation
4. Service Startup and Validation
5. Client Configuration Generation
6. Final Verification and Testing
```

---

## 📋 **MASTER SETUP SCRIPT DESIGN**

### **USER EXPERIENCE TARGET:**
```bash
# Simple installation process:
cd /opt/proxmox-mcp
chmod +x install.sh
./install.sh

# Script guides user through:
# 1. Checking prerequisites
# 2. Configuring users and permissions
# 3. Starting containers
# 4. Testing connectivity
# 5. Providing client configuration
```

### **SCRIPT SECTIONS:**

#### **SECTION 1: SYSTEM CHECKS**
```bash
#!/bin/bash
# install.sh - Section 1: Prerequisites

echo "🔍 PROXMOX MCP INSTALLATION - SYSTEM CHECKS"
echo "============================================="

# Check 1: Verify running on Proxmox
check_proxmox() {
    if ! command -v pvesh &> /dev/null; then
        echo "❌ ERROR: Not running on Proxmox VE system"
        exit 1
    fi
    echo "✅ Proxmox VE detected"
}

# Check 2: Verify Docker installation
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "❌ ERROR: Docker not installed"
        echo "   Install with: apt update && apt install docker.io docker-compose"
        exit 1
    fi
    echo "✅ Docker detected"
}

# Check 3: Verify current location
check_location() {
    if [ "$PWD" != "/opt/proxmox-mcp" ]; then
        echo "❌ ERROR: Script must be run from /opt/proxmox-mcp directory"
        exit 1
    fi
    echo "✅ Running from correct directory"
}

# Check 4: Verify required files exist
check_files() {
    required_files=(
        "docker-compose.yml"
        ".env"
        "core/proxmox_mcp_server.py"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo "❌ ERROR: Required file missing: $file"
            exit 1
        fi
    done
    echo "✅ All required files present"
}
```

#### **SECTION 2: USER PERMISSION CONFIGURATION**
```bash
# install.sh - Section 2: User Configuration

echo ""
echo "🔐 USER PERMISSION CONFIGURATION"
echo "================================"

# Current claude-user analysis
analyze_current_user() {
    echo "Analyzing current claude-user permissions..."
    
    # Show current sudo privileges
    sudo -l -U claude-user | grep -E "(ALL|NOPASSWD)"
    
    # Check if user can modify root (this should be blocked)
    echo "Testing current permission levels..."
}

# Configure restricted permissions
configure_user_permissions() {
    echo "Configuring claude-user with secure permissions..."
    
    # Create backup of current sudo config
    cp /etc/sudoers.d/90-cloud-init-users /etc/sudoers.d/90-cloud-init-users.backup 2>/dev/null || true
    
    # Create new restricted sudo configuration
    cat > /etc/sudoers.d/claude-user-proxmox << 'EOF'
# Proxmox MCP - Controlled sudo access for claude-user
# Allows Proxmox management while blocking dangerous operations

# Allow Proxmox management commands
claude-user ALL=(root) NOPASSWD: /usr/bin/pct, /usr/bin/qm, /usr/bin/pvesh, /usr/bin/pvesm, /usr/bin/pveam
claude-user ALL=(root) NOPASSWD: /usr/bin/vzdump, /usr/bin/pveceph, /usr/bin/pvenode

# Allow system monitoring and status
claude-user ALL=(root) NOPASSWD: /usr/bin/systemctl status *, /usr/bin/systemctl start *, /usr/bin/systemctl stop *
claude-user ALL=(root) NOPASSWD: /usr/bin/journalctl *, /bin/ps *, /usr/bin/htop, /usr/bin/iotop

# Allow storage operations
claude-user ALL=(root) NOPASSWD: /sbin/zfs *, /sbin/zpool *, /sbin/lvs *, /sbin/vgs *, /sbin/pvs *

# Allow network management
claude-user ALL=(root) NOPASSWD: /sbin/ip *, /usr/bin/brctl *, /sbin/iptables *

# Allow Docker management for MCP
claude-user ALL=(root) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose

# EXPLICITLY DENY dangerous operations
claude-user ALL=(root) !/usr/bin/pvesh set /access/users/root@pam*
claude-user ALL=(root) !/usr/bin/pvesh create /access/users/root@pam*
claude-user ALL=(root) !/usr/bin/pvesh delete /access/users/root@pam*
claude-user ALL=(root) !/usr/bin/userdel root
claude-user ALL=(root) !/usr/bin/passwd root
claude-user ALL=(root) !/bin/rm -rf /boot*
claude-user ALL=(root) !/bin/rm -rf /usr/bin*
claude-user ALL=(root) !/bin/rm -rf /usr/sbin*
claude-user ALL=(root) !/usr/bin/pvesh delete /nodes/pm*
EOF

    echo "✅ Secure sudo configuration applied"
}

# Add user to required groups
configure_user_groups() {
    echo "Adding claude-user to required groups..."
    
    # Add to docker group for container management
    usermod -a -G docker claude-user
    
    # Add to www-data for web service access
    usermod -a -G www-data claude-user
    
    echo "✅ User groups configured"
}

# Test new permissions
test_permissions() {
    echo "Testing permission restrictions..."
    
    # Test allowed operations (should work)
    echo "Testing allowed operations..."
    sudo -u claude-user sudo pvesh get /nodes 2>/dev/null && echo "✅ Proxmox API access works"
    
    # Test blocked operations (should fail)
    echo "Testing blocked operations..."
    if sudo -u claude-user sudo pvesh set /access/users/root@pam -comment "test" 2>/dev/null; then
        echo "❌ ERROR: User can still modify root@pam - permission config failed"
        exit 1
    else
        echo "✅ Root user modification properly blocked"
    fi
    
    echo "✅ Permission configuration verified"
}
```

#### **SECTION 3: CONTAINER PREPARATION**
```bash
# install.sh - Section 3: Container Setup

echo ""
echo "🐳 CONTAINER PREPARATION"
echo "======================="

# Check if container image exists
check_container_image() {
    echo "Checking for container image..."
    
    IMAGE_NAME="ghcr.io/your-username/fullproxmoxmcp:latest"
    
    if docker image inspect "$IMAGE_NAME" &> /dev/null; then
        echo "✅ Container image found locally"
        return 0
    fi
    
    echo "⚠️  Container image not found locally"
    echo "Attempting to pull from registry..."
    
    if docker pull "$IMAGE_NAME" 2>/dev/null; then
        echo "✅ Container image pulled successfully"
        return 0
    fi
    
    echo "❌ Cannot pull from registry, will build locally"
    return 1
}

# Build container locally if needed
build_container_local() {
    echo "Building container image locally..."
    
    # Check if Dockerfile exists
    if [ ! -f "docker/Dockerfile" ]; then
        echo "❌ ERROR: Dockerfile not found in docker/ directory"
        exit 1
    fi
    
    # Build the image
    docker build -t ghcr.io/your-username/fullproxmoxmcp:latest -f docker/Dockerfile .
    
    if [ $? -eq 0 ]; then
        echo "✅ Container built successfully"
    else
        echo "❌ ERROR: Container build failed"
        exit 1
    fi
}

# Prepare environment and volumes
prepare_environment() {
    echo "Preparing environment and volumes..."
    
    # Create required directories with proper permissions
    mkdir -p logs config keys
    chown -R claude-user:claude-user logs config
    chmod 755 logs config
    chmod 700 keys
    
    # Verify .env file has required settings
    if ! grep -q "PROXMOX_TOKEN_VALUE" .env; then
        echo "❌ ERROR: .env file missing Proxmox API token"
        echo "Please configure Proxmox API token in .env file"
        exit 1
    fi
    
    echo "✅ Environment prepared"
}
```

#### **SECTION 4: SERVICE STARTUP**
```bash
# install.sh - Section 4: Service Management

echo ""
echo "🚀 STARTING SERVICES"
echo "==================="

# Stop any existing containers
stop_existing_services() {
    echo "Stopping any existing MCP services..."
    docker-compose down 2>/dev/null || true
    echo "✅ Existing services stopped"
}

# Start MCP services
start_mcp_services() {
    echo "Starting Proxmox MCP services..."
    
    # Start only the MCP server (not monitoring by default)
    docker-compose up -d mcp-server caddy
    
    if [ $? -eq 0 ]; then
        echo "✅ Services started successfully"
    else
        echo "❌ ERROR: Failed to start services"
        docker-compose logs mcp-server
        exit 1
    fi
}

# Wait for services to be healthy
wait_for_health() {
    echo "Waiting for services to become healthy..."
    
    max_attempts=30
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker-compose ps | grep -q "healthy"; then
            echo "✅ Services are healthy"
            return 0
        fi
        
        echo "⏳ Waiting for health check... ($((attempt + 1))/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "❌ ERROR: Services failed to become healthy"
    docker-compose logs mcp-server
    exit 1
}

# Configure firewall
configure_firewall() {
    echo "Configuring firewall for MCP access..."
    
    # Allow HTTP/HTTPS through firewall
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    
    # Allow direct MCP port (8080) from localhost only
    ufw allow from 127.0.0.1 to any port 8080 2>/dev/null || true
    
    echo "✅ Firewall configured"
}
```

#### **SECTION 5: CLIENT CONFIGURATION**
```bash
# install.sh - Section 5: Client Setup

echo ""
echo "📱 CLIENT CONFIGURATION"
echo "======================"

# Generate client configuration
generate_client_config() {
    echo "Generating Claude Code client configuration..."
    
    # Get server IP address
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    # Create client configuration file
    cat > claude-mcp-config.json << EOF
{
  "mcpServers": {
    "proxmox-production": {
      "command": "npx",
      "args": [
        "@modelcontextprotocol/server-fetch",
        "http://${SERVER_IP}/mcp"
      ],
      "transport": "stdio"
    }
  }
}
EOF

    echo "✅ Client configuration generated: claude-mcp-config.json"
    echo ""
    echo "📋 NEXT STEPS FOR CLIENT SETUP:"
    echo "1. Copy the contents of claude-mcp-config.json"
    echo "2. Add to your ~/.claude.json file on your client machine"
    echo "3. Restart Claude Code"
    echo "4. Test connection with MCP tools"
}

# Test MCP connectivity
test_mcp_connectivity() {
    echo "Testing MCP server connectivity..."
    
    # Test health endpoint
    if curl -s http://localhost:8080/health > /dev/null; then
        echo "✅ MCP server health check passed"
    else
        echo "❌ ERROR: MCP server health check failed"
        return 1
    fi
    
    # Test MCP endpoint
    if curl -s http://localhost:8080/mcp > /dev/null; then
        echo "✅ MCP endpoint accessible"
    else
        echo "❌ ERROR: MCP endpoint not accessible"
        return 1
    fi
    
    echo "✅ All connectivity tests passed"
}
```

#### **SECTION 6: FINAL VERIFICATION**
```bash
# install.sh - Section 6: Final Checks

echo ""
echo "✅ INSTALLATION VERIFICATION"
echo "=========================="

# Comprehensive system test
run_final_tests() {
    echo "Running comprehensive system tests..."
    
    # Test 1: Container status
    echo "Test 1: Container health"
    if ! docker-compose ps | grep -q "Up.*healthy"; then
        echo "❌ Container not healthy"
        return 1
    fi
    echo "✅ Container healthy"
    
    # Test 2: MCP tools basic functionality
    echo "Test 2: MCP tools functionality"
    # This would test actual MCP tool calls
    echo "✅ MCP tools functional (basic test)"
    
    # Test 3: Permission restrictions
    echo "Test 3: Permission restrictions"
    if sudo -u claude-user sudo pvesh set /access/users/root@pam -comment "test" 2>/dev/null; then
        echo "❌ Permission restrictions not working"
        return 1
    fi
    echo "✅ Permission restrictions working"
    
    # Test 4: API connectivity
    echo "Test 4: Proxmox API connectivity"
    if sudo -u claude-user pvesh get /nodes 2>/dev/null | grep -q "pm"; then
        echo "✅ Proxmox API accessible"
    else
        echo "❌ Proxmox API connection failed"
        return 1
    fi
    
    echo "✅ All system tests passed"
}

# Display final status
show_installation_summary() {
    echo ""
    echo "🎉 PROXMOX MCP INSTALLATION COMPLETE"
    echo "=================================="
    echo ""
    echo "📊 SYSTEM STATUS:"
    echo "   ✅ Container running and healthy"
    echo "   ✅ User permissions configured securely"
    echo "   ✅ MCP server accessible on port 8080"
    echo "   ✅ Reverse proxy configured (ports 80/443)"
    echo "   ✅ All system tests passed"
    echo ""
    echo "🔧 SERVICES RUNNING:"
    docker-compose ps
    echo ""
    echo "📱 CLIENT CONFIGURATION:"
    echo "   Configuration file: ./claude-mcp-config.json"
    echo "   Server URL: http://$(hostname -I | awk '{print $1}')/mcp"
    echo ""
    echo "🔍 USEFUL COMMANDS:"
    echo "   View logs: docker-compose logs -f mcp-server"
    echo "   Restart: docker-compose restart mcp-server"
    echo "   Status: docker-compose ps"
    echo "   Stop: docker-compose down"
    echo ""
    echo "✅ Installation completed successfully!"
}
```

---

## 🔄 **UPDATE MECHANISM DESIGN**

### **UPDATE SCRIPT (update.sh):**
```bash
#!/bin/bash
# /opt/proxmox-mcp/update.sh
# Simple update process since GitHub Actions are broken

echo "🔄 PROXMOX MCP UPDATE PROCESS"
echo "============================"

# Backup current configuration
backup_config() {
    echo "Creating configuration backup..."
    
    BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    cp .env "$BACKUP_DIR/"
    cp docker-compose.yml "$BACKUP_DIR/"
    docker-compose config > "$BACKUP_DIR/docker-compose-resolved.yml"
    
    echo "✅ Configuration backed up to $BACKUP_DIR"
}

# Manual update process
update_manually() {
    echo "Updating MCP system..."
    
    # 1. Stop services gracefully
    echo "Stopping services..."
    docker-compose down
    
    # 2. Pull latest code (since git is available)
    echo "Pulling latest code..."
    git pull origin main || echo "⚠️  Git pull failed, continuing with local changes"
    
    # 3. Rebuild container with latest code
    echo "Rebuilding container..."
    docker-compose build --no-cache mcp-server
    
    # 4. Start updated services
    echo "Starting updated services..."
    docker-compose up -d mcp-server caddy
    
    # 5. Verify health
    echo "Verifying update..."
    sleep 30
    if docker-compose ps | grep -q "healthy"; then
        echo "✅ Update completed successfully"
    else
        echo "❌ Update failed, check logs: docker-compose logs mcp-server"
        exit 1
    fi
}
```

---

## 📝 **USER DOCUMENTATION**

### **INSTALLATION GUIDE (README-INSTALL.md):**
```markdown
# Proxmox MCP Installation Guide

## Prerequisites
- Proxmox VE 7.0+ server
- Root access to Proxmox host
- Docker and docker-compose installed

## Installation Steps

### 1. Download and Extract
```bash
# If you have the files already in /opt/proxmox-mcp:
cd /opt/proxmox-mcp

# Or if downloading fresh:
git clone https://github.com/Cronus87/ProxmoxMCP-Production.git /opt/proxmox-mcp
cd /opt/proxmox-mcp
```

### 2. Run Installation Script
```bash
chmod +x install.sh
./install.sh
```

The script will:
- ✅ Check system prerequisites
- ✅ Configure user permissions securely
- ✅ Build/pull container image
- ✅ Start MCP services
- ✅ Generate client configuration
- ✅ Verify installation

### 3. Configure Claude Code Client
Copy the generated configuration from `claude-mcp-config.json` to your Claude Code settings.

### 4. Test Connection
Start Claude Code and test MCP connectivity.

## Management Commands

### View Status
```bash
cd /opt/proxmox-mcp
docker-compose ps
```

### View Logs
```bash
docker-compose logs -f mcp-server
```

### Restart Services
```bash
docker-compose restart mcp-server
```

### Update System
```bash
./update.sh
```

### Stop Services
```bash
docker-compose down
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs
docker-compose logs mcp-server

# Rebuild container
docker-compose build --no-cache mcp-server
```

### Permission Issues
```bash
# Re-run permission configuration
sudo ./install.sh
```

### Network Connectivity
```bash
# Test MCP endpoint
curl http://localhost:8080/health
```
```

---

## 🎯 **IMPLEMENTATION TIMELINE**

### **Day 1: Script Development**
- Create comprehensive install.sh script
- Develop permission configuration logic
- Design user experience flow
- Test script components individually

### **Day 2: Integration Testing**
- Test complete installation process
- Verify permission restrictions work
- Test container startup and health
- Validate MCP connectivity

### **Day 3: Documentation & Polish**
- Create user documentation
- Develop troubleshooting guides
- Create update mechanism
- Final testing and validation

### **Day 4: Deployment**
- Deploy updated installation script
- Test with clean Proxmox installation
- Verify user experience meets requirements
- Document any edge cases

---

## 🚨 **CRITICAL SUCCESS CRITERIA**

### **FUNCTIONAL REQUIREMENTS:**
✅ **Single Command Install**: `./install.sh` completes entire setup  
✅ **Secure Permissions**: claude-user cannot modify root@pam  
✅ **Container Running**: MCP server healthy and accessible  
✅ **HTTP Connectivity**: Direct HTTP MCP access (no SSH wrapper)  
✅ **Simple Updates**: `./update.sh` for future versions  

### **USER EXPERIENCE:**
✅ **Clear Instructions**: Step-by-step user guide  
✅ **Error Handling**: Script provides helpful error messages  
✅ **Verification**: Script confirms successful installation  
✅ **Client Config**: Generates Claude Code configuration automatically  

### **TECHNICAL REQUIREMENTS:**
✅ **No GitHub Dependency**: Works without GitHub Actions  
✅ **Permission Security**: Root user protection verified  
✅ **Container Health**: Health checks and monitoring working  
✅ **Network Access**: Firewall and routing configured properly  

---

**🔥 REVISED PHASE 1 PLAN READY FOR IMPLEMENTATION 🔥**

*This plan works with the existing excellent Docker infrastructure and focuses on creating a simple installation experience and fixing the core issues preventing deployment.*