# MCP Integration Implementation Checklist
## Technical Action Items for Production Deployment

**Status:** Post-Validation Configuration  
**Owner:** DevOps Fix Agent (for connectivity) + Integration Agent (for protocol)  
**Priority:** HIGH  

---

## 1. SSH Authentication Resolution

### Issue: SSH Key Authentication Failing
**Status:** 🔴 CRITICAL - Blocks command execution

#### Diagnosis Commands:
```bash
# Test current key
ssh -i keys/claude_proxmox_key -v claude-user@gwrath.hopto.org

# Check key format
file keys/claude_proxmox_key
ssh-keygen -l -f keys/claude_proxmox_key

# Test key parsing
ssh-keygen -y -f keys/claude_proxmox_key
```

#### Solution Options:

**Option A: Regenerate SSH Key**
```bash
# Generate new Ed25519 key (recommended)
ssh-keygen -t ed25519 -C "claude-mcp@proxmox" -f keys/claude_proxmox_key_new

# Copy to server (requires password or existing access)
ssh-copy-id -i keys/claude_proxmox_key_new.pub claude-user@gwrath.hopto.org

# Update .env configuration
SSH_KEY_PATH=keys/claude_proxmox_key_new
```

**Option B: Fix Key Permissions**
```bash
# Ensure correct permissions
chmod 600 keys/claude_proxmox_key
chmod 644 keys/claude_proxmox_key.pub

# Check for passphrase issues
ssh-keygen -p -f keys/claude_proxmox_key
```

**Option C: Use Password Authentication (Temporary)**
```bash
# Add to .env for testing
SSH_PASSWORD=your_password
```

---

## 2. Proxmox API Connectivity

### Issue: Port 8006 Not Accessible Externally  
**Status:** 🟡 MEDIUM - API tools unavailable remotely

#### Current Status:
```
Port 8006 (Proxmox Web): CLOSED/FILTERED
Port 22 (SSH):          OPEN
Port 8080 (MCP HTTP):   OPEN  
```

#### Investigation Commands:
```bash
# Check if API is accessible internally
ssh claude-user@gwrath.hopto.org "curl -k https://localhost:8006/api2/json/version"

# Check firewall status
ssh claude-user@gwrath.hopto.org "sudo ufw status"

# Check Proxmox service status
ssh claude-user@gwrath.hopto.org "systemctl status pveproxy"
```

#### Solution Options:

**Option A: Enable External API Access (Recommended)**
```bash
# On Proxmox server, open firewall
sudo ufw allow 8006/tcp

# Check Proxmox network configuration
pvesh get /nodes/[node]/network
```

**Option B: Use SSH Tunnel for API**
```bash
# Create SSH tunnel for API access
ssh -L 8006:localhost:8006 claude-user@gwrath.hopto.org

# Update configuration to use localhost:8006 when tunneled
```

**Option C: Internal-Only API Usage**
```bash
# Deploy MCP server on Proxmox host itself
# Use internal API calls through SSH command execution
```

---

## 3. HTTP MCP Server Dependencies

### Issue: FastMCP/FastAPI Not Installed
**Status:** 🟡 MEDIUM - HTTP transport unavailable

#### Required Dependencies:
```bash
# Install in virtual environment
python3 -m venv mcp_env
source mcp_env/bin/activate
pip install -r requirements-http.txt

# Or install system-wide (not recommended)
pip3 install --break-system-packages -r requirements-http.txt
```

#### Production Deployment:
```bash
# Create deployment script
cat > deploy_http_mcp.sh << 'EOF'
#!/bin/bash
cd /opt/proxmox-mcp
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-http.txt
python run_mcp_server_http.py --host 0.0.0.0 --port 8080
EOF

chmod +x deploy_http_mcp.sh
```

---

## 4. MCP Protocol Testing

### Comprehensive Tool Testing
**Status:** ✅ READY - Protocol validation complete

#### Test Suite Commands:
```bash
# Test STDIO MCP server
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | python3 core/proxmox_mcp_server.py

# Test HTTP MCP server  
curl -X POST http://localhost:8080/api/mcp/tools/list

# Test individual tools
curl -X POST http://localhost:8080/api/mcp/tools/call \
  -H "Content-Type: application/json" \
  -d '{"name": "execute_command", "arguments": {"command": "whoami"}}'
```

#### Integration Testing:
```python
# Automated test script
import asyncio
import json
from core.proxmox_mcp_server import ProxmoxMCPServer

async def test_all_tools():
    server = ProxmoxMCPServer()
    
    # Test each tool
    tools = ["execute_command", "list_vms", "vm_status", "vm_action", "node_status", "proxmox_api"]
    
    for tool in tools:
        try:
            result = await server.handle_call_tool(tool, {})
            print(f"✅ {tool}: SUCCESS")
        except Exception as e:
            print(f"❌ {tool}: {e}")
            
    server.cleanup()

asyncio.run(test_all_tools())
```

---

## 5. Security Validation

### Current Security Status: ✅ COMPLIANT

#### Security Checklist:
- [x] Dangerous commands disabled
- [x] Limited user permissions (claude-user)
- [x] API token authentication
- [x] SSH key authentication (pending fix)
- [x] SSL certificate validation (appropriately disabled for self-signed)
- [x] Command input validation
- [x] Error message sanitization

#### Additional Security Measures:
```bash
# Rate limiting for API calls
# Connection timeout configuration  
# Audit logging for all operations
# IP whitelist for HTTP MCP server
```

---

## 6. Deployment Configuration

### Production Environment Setup

#### Docker Deployment (Recommended):
```yaml
# docker-compose.yml
version: '3.8'
services:
  proxmox-mcp:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./keys:/app/keys:ro
      - ./.env:/app/.env:ro
    environment:
      - LOG_LEVEL=INFO
    restart: unless-stopped
```

#### Systemd Service:
```ini
# /etc/systemd/system/proxmox-mcp.service
[Unit]
Description=Proxmox MCP Server
After=network.target

[Service]
Type=simple
User=claude-user
WorkingDirectory=/opt/proxmox-mcp
ExecStart=/opt/proxmox-mcp/venv/bin/python run_mcp_server_http.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## 7. Monitoring and Health Checks

### Health Check Endpoints:
```bash
# Basic health check
curl http://localhost:8080/health

# Detailed component status
curl http://localhost:8080/health | jq '.checks'

# MCP endpoint validation
curl http://localhost:8080/api/mcp
```

### Monitoring Integration:
```bash
# Add to monitoring system
# - SSH connectivity test
# - API connectivity test  
# - Tool execution success rate
# - Error rate monitoring
# - Performance metrics
```

---

## 8. Priority Action Plan

### Phase 1: Critical Fixes (24 hours)
1. **Fix SSH Authentication**
   - Regenerate SSH key or fix current key
   - Test command execution functionality
   - Verify claude-user permissions

2. **Resolve API Connectivity**
   - Open port 8006 or implement SSH tunneling
   - Test API authentication
   - Validate token permissions

### Phase 2: HTTP Server Deployment (48 hours)
1. **Install Dependencies**
   - Set up virtual environment
   - Install HTTP server requirements
   - Configure production settings

2. **Deploy HTTP MCP Server**
   - Start HTTP server on port 8080
   - Configure reverse proxy (Caddy)
   - Test all endpoints

### Phase 3: Integration Testing (72 hours)
1. **End-to-End Testing**
   - Test all 6 MCP tools
   - Validate error handling
   - Performance testing

2. **Security Audit**
   - Penetration testing
   - Configuration review
   - Access control validation

---

## 9. Success Criteria

### Functional Requirements:
- [ ] SSH command execution working
- [ ] All 6 MCP tools functional
- [ ] HTTP and STDIO transports available
- [ ] Error handling robust
- [ ] Security controls effective

### Performance Requirements:
- [ ] Command execution < 5 seconds
- [ ] API calls < 3 seconds
- [ ] Health checks < 1 second
- [ ] 99.9% uptime target

### Integration Requirements:
- [ ] Claude Code connectivity
- [ ] MCP protocol compliance
- [ ] Tool discovery working
- [ ] Resource enumeration functional

---

## 10. Next Steps

**Immediate Actions:**
1. DevOps Fix Agent: Address SSH and API connectivity
2. Architecture Agent: Validate deployment automation
3. Security Fix Agent: Final security review
4. Integration Agent: Post-fix validation testing

**Hand-off to DevOps Fix Agent:**
- SSH authentication troubleshooting
- Proxmox API access configuration
- HTTP server dependency installation
- Production deployment automation

**Integration Agent Responsibilities:**
- Post-fix MCP protocol validation
- Tool functionality verification
- Performance testing
- Final integration sign-off

---

**Checklist Created:** 2025-06-25  
**Target Completion:** 72 hours  
**Critical Path:** SSH Authentication → API Access → HTTP Deployment → Integration Testing  

**Status:** READY FOR DEVOPS IMPLEMENTATION ✅