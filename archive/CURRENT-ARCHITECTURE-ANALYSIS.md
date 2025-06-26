# CURRENT PROXMOX MCP ARCHITECTURE - DETAILED ANALYSIS

**Status**: ❌ **NOT SELF-CONTAINED** - Requires External Development Machine  
**Date**: June 26, 2025  
**Goal**: Document current setup to plan migration to 100% self-contained system

---

## 🏗️ **CURRENT ARCHITECTURE OVERVIEW**

```
┌─────────────────────┐    SSH Wrapper     ┌─────────────────────┐    Local Exec    ┌─────────────────────┐
│  Development WSL    │────────────────────▶│   Proxmox Server   │──────────────────▶│   Command Target   │
│  (glrowe machine)   │                     │   (gwrath.hopto.org)│                   │   (claude-user)     │
└─────────────────────┘                     └─────────────────────┘                   └─────────────────────┘
         │                                           │                                          │
         ▼                                           ▼                                          ▼
┌─────────────────────┐                     ┌─────────────────────┐                   ┌─────────────────────┐
│ Claude Code Client  │                     │ MCP Server Process  │                   │ SSH Session (claude)│
│ ~/.claude.json      │                     │ /opt/proxmox-mcp/   │                   │ /home/claude-user   │
│ proxmox-production  │                     │ python run_mcp...   │                   │ whoami = claude-user│
└─────────────────────┘                     └─────────────────────┘                   └─────────────────────┘
```

---

## 🖥️ **COMPONENT BREAKDOWN**

### **1. DEVELOPMENT MACHINE (WSL2 Ubuntu)**
- **Location**: `/mnt/d/VS Code Projects/ProxmoxMCP-Production/`
- **User**: `glrowe`
- **OS**: `Linux 5.15.167.4-microsoft-standard-WSL2`

**Key Files:**
```
/home/glrowe/
├── .ssh/proxmox_mcp_deploy          # SSH private key for Proxmox access
├── proxmox-mcp-wrapper.sh           # ⚠️ CRITICAL: SSH wrapper script
└── .claude.json                    # Claude Code MCP configuration
```

**Claude Code Configuration (`~/.claude.json`):**
```json
{
  "mcpServers": {
    "proxmox-production": {
      "command": "/home/glrowe/proxmox-mcp-wrapper.sh",
      "transport": "stdio"
    }
  }
}
```

**SSH Wrapper Script (`~/proxmox-mcp-wrapper.sh`):**
```bash
#!/bin/bash
ssh -i /home/glrowe/.ssh/proxmox_mcp_deploy root@gwrath.hopto.org 'cd /opt/proxmox-mcp && source venv/bin/activate && python run_mcp_server.py'
```

---

### **2. PROXMOX SERVER (Production Host)**
- **Hostname**: `pm`
- **FQDN**: `gwrath.hopto.org`
- **OS**: `Linux 6.8.12-11-pve` (Proxmox VE)
- **Architecture**: `x86_64`

**Installation Directory Structure:**
```
/opt/proxmox-mcp/                    # Main installation directory
├── .env                             # Environment configuration
├── core/                            # MCP server core components
│   ├── proxmox_mcp_server.py       # Main MCP server implementation
│   ├── environment_manager.py      # Environment detection
│   └── proxmox_mcp_server.py.backup # Backup file
├── venv/                            # Python virtual environment
├── keys/                            # SSH keys directory
│   └── claude_proxmox_key          # SSH key for claude-user auth
├── run_mcp_server.py               # STDIO MCP server runner
├── run_mcp_server_http.py          # HTTP MCP server (unused)
├── mcp_server.log                  # Server logs
└── requirements.txt                # Python dependencies
```

**Environment Configuration (`.env`):**
```env
# SSH Configuration
SSH_TARGET=proxmox
SSH_HOST=gwrath.hopto.org
SSH_USER=claude-user
SSH_PORT=22
ENABLE_SSH=true
SSH_KEY_PATH=/opt/proxmox-mcp/keys/claude_proxmox_key

# Proxmox API Configuration
PROXMOX_HOST=localhost
PROXMOX_USER=root@pam
PROXMOX_TOKEN_NAME=claude-mcp
PROXMOX_TOKEN_VALUE=2de410bd-4a87-46dc-8517-b411b36d708b
PROXMOX_VERIFY_SSL=false

# Feature Configuration
ENABLE_PROXMOX_API=true
ENABLE_DANGEROUS_COMMANDS=false
ENABLE_LOCAL_EXECUTION=false
```

---

### **3. USER ACCOUNTS & PERMISSIONS**

**Root User (`root`):**
- **Purpose**: MCP server process execution
- **SSH Access**: Via `/home/glrowe/.ssh/proxmox_mcp_deploy`
- **Process Owner**: MCP server runs as root (PID 1446674)

**Claude User (`claude-user`):**
- **UID/GID**: `1001/1002`
- **Groups**: `claude-user sudo`
- **Sudo Privileges**: `(ALL : ALL) ALL` and `(ALL) NOPASSWD: ALL`
- **Working Directory**: `/home/claude-user`
- **SSH Access**: Via `/opt/proxmox-mcp/keys/claude_proxmox_key`

**Proxmox Users:**
```
claude-user@pam    # Limited Proxmox user (intended)
root@pam          # Full Proxmox admin (can be modified by claude-user!)
```

---

## 🔄 **CURRENT EXECUTION FLOW**

### **Step-by-Step Process:**

1. **Claude Code Startup**:
   ```bash
   # User runs: claude
   # Claude Code reads ~/.claude.json
   # Identifies MCP server: proxmox-production
   ```

2. **MCP Connection Initiation**:
   ```bash
   # Claude Code executes: /home/glrowe/proxmox-mcp-wrapper.sh
   # Wrapper script runs SSH command to Proxmox
   ```

3. **SSH Connection**:
   ```bash
   ssh -i /home/glrowe/.ssh/proxmox_mcp_deploy root@gwrath.hopto.org \
     'cd /opt/proxmox-mcp && source venv/bin/activate && python run_mcp_server.py'
   ```

4. **MCP Server Startup**:
   ```python
   # On Proxmox: python run_mcp_server.py
   # Process runs as: root (PID 1446674)
   # Loads config from: /opt/proxmox-mcp/.env
   # Establishes STDIO connection back to Claude Code
   ```

5. **Command Execution**:
   ```bash
   # User requests: whoami via MCP
   # MCP server on Proxmox receives request
   # MCP server makes SSH connection: claude-user@gwrath.hopto.org
   # Command executes as: claude-user
   # Result returns: claude-user
   ```

---

## 🚨 **DEPENDENCIES & SINGLE POINTS OF FAILURE**

### **External Dependencies:**
1. **Development Machine Availability**:
   - Must be powered on and connected
   - WSL2 environment must be running
   - SSH wrapper script must be accessible

2. **Network Connectivity**:
   - Development machine → Proxmox SSH (port 22)
   - Proxmox → Self SSH (localhost SSH for command execution)

3. **SSH Key Chain**:
   - `proxmox_mcp_deploy` key (dev machine → Proxmox root)
   - `claude_proxmox_key` key (Proxmox → claude-user)

4. **File System Dependencies**:
   - `/home/glrowe/.ssh/proxmox_mcp_deploy` (local)
   - `/home/glrowe/proxmox-mcp-wrapper.sh` (local)
   - `/opt/proxmox-mcp/` (Proxmox)

### **Single Points of Failure:**
- ❌ **Development machine offline** → MCP unavailable
- ❌ **SSH wrapper script missing** → MCP unavailable  
- ❌ **Network issues** → MCP unavailable
- ❌ **SSH key corruption** → Authentication failure

---

## 🔐 **SECURITY MODEL ANALYSIS**

### **Current Security Layers:**

1. **Network Security**:
   - SSH key authentication (RSA 2048-bit)
   - No password authentication
   - Port 22 access required

2. **User Privilege Separation**:
   - MCP server runs as: `root`
   - Commands execute as: `claude-user`
   - API calls use: `root@pam` with token

3. **Command Filtering**:
   - Dangerous commands blocked by default
   - `ENABLE_DANGEROUS_COMMANDS=false`

### **🚨 SECURITY VULNERABILITIES IDENTIFIED:**

1. **Excessive claude-user Privileges**:
   ```bash
   # claude-user can modify root@pam user!
   sudo pvesh set /access/users/root@pam -comment "modified"
   # ✅ SUCCEEDS - SECURITY VIOLATION
   ```

2. **MCP Server Running as Root**:
   - Process ID 1446674 runs as root
   - Unnecessary privilege escalation

3. **SSH Key Exposure**:
   - Multiple SSH keys in different locations
   - Keys accessible to development machine user

4. **No Session Management**:
   - No connection limits
   - No audit logging of MCP sessions

---

## 📊 **PERFORMANCE & RELIABILITY ISSUES**

### **Current Performance Bottlenecks:**

1. **Double SSH Overhead**:
   ```
   Dev Machine → SSH → Proxmox (MCP Server) → SSH → claude-user (Command)
   ```

2. **Network Latency**:
   - Every command requires network round-trip
   - SSH connection establishment overhead

3. **Process Management**:
   - MCP server process orphaned when dev machine disconnects
   - No automatic restart mechanism

### **Reliability Concerns:**

1. **No Service Management**:
   - MCP server not managed by systemd
   - Manual process start/stop

2. **Log Management**:
   - Logs accumulate in `/opt/proxmox-mcp/mcp_server.log`
   - No log rotation configured

3. **Dependency Management**:
   - Python virtual environment in `/opt/proxmox-mcp/venv/`
   - No automatic dependency updates

---

## 🎯 **MIGRATION PLAN TO SELF-CONTAINED SYSTEM**

### **Phase 1: HTTP MCP Server**
```
┌─────────────────────┐    HTTP API     ┌─────────────────────┐
│   Claude Code       │────────────────▶│   Proxmox Server   │
│   (Any Location)    │                 │   HTTP:8080/mcp     │
└─────────────────────┘                 └─────────────────────┘
```

**Required Changes:**
1. **Enable HTTP MCP Server**: Use `run_mcp_server_http.py`
2. **Systemd Service**: Create service for automatic startup
3. **Remove SSH Dependencies**: Direct local execution
4. **Claude Code Config**: Point to HTTP endpoint

### **Phase 2: Enhanced Security**
1. **API Authentication**: Add token-based auth
2. **User Privilege Reduction**: Run MCP as claude-user
3. **Command Validation**: Enhanced security filtering
4. **Session Management**: Connection limits and logging

### **Phase 3: Production Hardening**
1. **SSL/TLS**: Encrypt HTTP communications
2. **Firewall Rules**: Restrict access to MCP port
3. **Monitoring**: Health checks and alerting
4. **Backup/Recovery**: Configuration backup strategy

---

## 📝 **IMMEDIATE ACTION ITEMS**

### **Short Term (Security Fixes):**
1. ✅ **Document current architecture** (this document)
2. ⚠️ **Reduce claude-user privileges** (currently too high)
3. ⚠️ **Run MCP server as claude-user instead of root**
4. ⚠️ **Implement additional command filtering**

### **Medium Term (Self-Contained Migration):**
1. 🔄 **Test HTTP MCP server functionality**
2. 🔄 **Create systemd service for MCP**
3. 🔄 **Implement local execution without SSH**
4. 🔄 **Update Claude Code configuration**

### **Long Term (Production Hardening):**
1. 🔮 **Add API authentication layer**
2. 🔮 **Implement SSL/TLS encryption**
3. 🔮 **Create monitoring and alerting**
4. 🔮 **Develop backup/recovery procedures**

---

## 🔧 **CONFIGURATION REFERENCES**

### **Key Configuration Files:**

**Local Machine:**
- `~/.claude.json` - Claude Code MCP configuration
- `~/proxmox-mcp-wrapper.sh` - SSH wrapper script
- `~/.ssh/proxmox_mcp_deploy` - SSH private key

**Proxmox Server:**
- `/opt/proxmox-mcp/.env` - Environment configuration
- `/opt/proxmox-mcp/run_mcp_server.py` - STDIO server
- `/opt/proxmox-mcp/run_mcp_server_http.py` - HTTP server (unused)
- `/opt/proxmox-mcp/keys/claude_proxmox_key` - Internal SSH key

### **Network Ports:**
- **SSH**: `22` (gwrath.hopto.org)
- **Proxmox Web**: `8006` (HTTPS)
- **MCP HTTP** (future): `8080` (HTTP)

### **Process Information:**
```bash
# Current MCP server process:
root     1446674  0.0  0.1 311668 73672 ?        Ssl  Jun25   0:01 python run_mcp_server.py

# Command execution user:
claude-user (UID 1001, GID 1002)
```

---

**🎯 GOAL**: Transform this architecture into a fully self-contained Proxmox service that requires no external dependencies and can be accessed via HTTP from any Claude Code session without SSH wrapper scripts.

---

*Generated: June 26, 2025 - Current Architecture Analysis for Future Self-Contained Migration*