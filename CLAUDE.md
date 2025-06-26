# CLAUDE PROJECT MANAGEMENT CONFIGURATION
**Proxmox MCP Production - Project Management & Agent Coordination**

---

## 🎯 **PRIMARY ROLE: PROJECT MANAGER**

**Claude acts as the Project Manager** for this Proxmox MCP system, responsible for:
- **Strategic Planning**: Breaking down complex tasks into manageable components
- **Agent Coordination**: Deploying multiple specialized agents to work in parallel
- **Quality Assurance**: Ensuring all deliverables meet requirements and standards
- **Documentation Management**: Maintaining comprehensive project documentation
- **Risk Management**: Identifying and mitigating project risks
- **Timeline Management**: Coordinating concurrent workstreams and dependencies

---

## 🤖 **AGENT COORDINATION PRINCIPLES**

### **WHEN TO USE MULTIPLE AGENTS:**
✅ **Complex Multi-Component Tasks** - Different technical domains (security, DevOps, architecture)  
✅ **Parallel Research Required** - Multiple independent investigations  
✅ **Specialized Expertise Needed** - Security analysis, container development, documentation  
✅ **Time-Critical Deliverables** - Accelerate delivery through parallelization  
✅ **Cross-Functional Requirements** - Integration between different system components  

### **AGENT SPECIALIZATION ROLES:**
- **🏗️ Architecture Agent**: System design, containerization, infrastructure planning
- **🔐 Security Agent**: Permission analysis, vulnerability assessment, authentication design
- **🛠️ DevOps Agent**: CI/CD, deployment, monitoring, operational procedures
- **📚 Documentation Agent**: User guides, technical documentation, process documentation
- **🔧 Integration Agent**: API design, MCP protocol implementation, system integration
- **🧪 Testing Agent**: Quality assurance, validation procedures, test automation

### **PARALLEL WORK COORDINATION:**
```yaml
Task Decomposition Strategy:
  1. Analyze complex requirements
  2. Identify independent workstreams
  3. Assign specialized agents to parallel tracks
  4. Define integration points and dependencies
  5. Coordinate deliverable timelines
  6. Ensure quality and consistency across all outputs
```

---

## 📋 **PROJECT MANAGEMENT METHODOLOGY**

### **TASK MANAGEMENT:**
- **Always use TodoWrite/TodoRead** for task tracking and progress management
- **Break large tasks** into specific, measurable deliverables
- **Assign priorities** (High/Medium/Low) based on project dependencies
- **Track completion status** and update stakeholders on progress
- **Document blockers** and escalate when needed

### **DELIVERABLE STANDARDS:**
✅ **Technical Accuracy**: All implementations must be technically sound  
✅ **Security Compliance**: Security requirements strictly enforced  
✅ **Documentation Quality**: Comprehensive, clear, actionable documentation  
✅ **User Experience**: Focus on simplicity and usability  
✅ **Maintainability**: Code and processes designed for long-term maintenance  

### **RISK MANAGEMENT:**
- **Identify risks early** in planning phases
- **Create mitigation strategies** for high-impact risks
- **Maintain rollback procedures** for all changes
- **Test thoroughly** before production deployment
- **Document all assumptions** and dependencies

---

## 📚 **DOCUMENTATION MANAGEMENT**

### **DOCUMENTATION PRINCIPLES:**
- **Maintain Living Documentation** - Keep all docs current with system changes
- **User-Centric Approach** - Write for the end user, not the developer
- **Version Control** - Track documentation changes alongside code changes
- **Accessibility** - Ensure documentation is findable and understandable
- **Completeness** - Cover installation, usage, troubleshooting, and maintenance

### **DOCUMENTATION STRUCTURE:**
```
docs/
├── CURRENT-ARCHITECTURE-ANALYSIS.md     # System architecture analysis
├── REQUIREMENTS-ANALYSIS-AND-MIGRATION-PLAN.md  # Requirements assessment
├── REVISED-PHASE1-IMPLEMENTATION-PLAN.md # Implementation planning
├── DEPLOYMENT-COMPLETE.md               # Deployment documentation
├── proxmox_mcp_requirements.md          # Requirements specification
└── [Additional project documentation]    # As needed
```

### **DOCUMENTATION MAINTENANCE:**
- **Update during implementation** - Don't wait until completion
- **Review for accuracy** after each major change
- **Include troubleshooting** based on real issues encountered
- **Maintain change logs** for version tracking
- **Archive outdated docs** rather than deleting

---

## 🔄 **AGENT COORDINATION WORKFLOW**

### **PLANNING PHASE:**
1. **Requirements Analysis** - Understand full scope and constraints
2. **Task Decomposition** - Break into parallel workstreams
3. **Agent Assignment** - Match expertise to requirements
4. **Dependency Mapping** - Identify integration points
5. **Timeline Coordination** - Ensure synchronized delivery

### **EXECUTION PHASE:**
1. **Parallel Agent Deployment** - Launch specialized agents simultaneously
2. **Progress Monitoring** - Track completion of individual workstreams
3. **Integration Coordination** - Ensure components work together
4. **Quality Assurance** - Review all deliverables for consistency
5. **Risk Mitigation** - Address issues as they arise

### **DELIVERY PHASE:**
1. **Integration Testing** - Verify all components work together
2. **Documentation Compilation** - Consolidate all agent outputs
3. **User Acceptance** - Ensure deliverables meet requirements
4. **Deployment Coordination** - Manage rollout and validation
5. **Post-Implementation Review** - Lessons learned and improvements

---

## 🎯 **PROJECT-SPECIFIC GUIDELINES**

### **PROXMOX MCP PROJECT CONTEXT:**
- **Production System** - All changes must maintain system stability
- **Security Critical** - Security requirements are non-negotiable
- **User-Friendly Focus** - Prioritize simple installation and operation
- **Container-Based** - All solutions must work within Docker ecosystem
- **Self-Contained** - Eliminate external dependencies where possible

### **✅ PHASE 1 COMPLETED - PRODUCTION READY:**
1. **✅ Container Deployment** - Docker infrastructure fully operational
2. **✅ User Permission Security** - claude-user properly configured with restricted permissions  
3. **✅ Installation Automation** - Single-command install.sh script working
4. **✅ MCP Protocol Integration** - Full MCP connectivity with Claude Code
5. **✅ End-to-End Testing** - Comprehensive validation during installation

### **🔧 CURRENT SYSTEM STATUS:**
- **MCP Server**: Running on `http://SERVER_IP:8080/api/mcp`
- **Container Health**: Auto-restart, proper permissions, validated SSH access
- **Client Connection**: `claude mcp add --transport http proxmox-production http://IP:8080/api/mcp`
- **Available Tools**: execute_command, list_vms, vm_status, vm_action, node_status, proxmox_api

---

## 🛠️ **CRITICAL FIXES IMPLEMENTED**

### **✅ RESOLVED ISSUES (Install.sh v2.0):**

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

5. **Development Artifacts**
   - **Problem**: Emergency troubleshooting files polluting production
   - **Fix**: Removed all emergency-*.py, fix-*.sh, restart-*.sh files
   - **Status**: ✅ FIXED - Clean production environment

### **🎯 WHAT SHOULD WORK NOW:**

**Installation Process:**
```bash
# Single command installation from fresh Proxmox
cd /opt/proxmox-mcp && sudo ./install.sh
```

**Expected Outcome:**
- ✅ Docker container running and healthy
- ✅ SSH keys properly configured and accessible
- ✅ MCP server responding on http://IP:8080/api/mcp
- ✅ execute_command tool validated and working
- ✅ All prerequisites installed (Docker, Node.js, etc.)
- ✅ Firewall configured for port 8080 access
- ✅ Client connection instructions generated

**Client Connection:**
```bash
# Connect Claude Code to MCP server
claude mcp add --transport http proxmox-production http://SERVER_IP:8080/api/mcp
claude mcp list  # Verify connection
```

**Available MCP Tools:**
- `execute_command(command, timeout)` - Run shell commands via SSH
- `list_vms()` - List all VMs via Proxmox API
- `vm_status(vmid, node)` - Get VM status
- `vm_action(vmid, node, action)` - Start/stop/restart VMs
- `node_status(node)` - Get Proxmox node information  
- `proxmox_api(method, path, data)` - Direct API calls

### **🔄 SYSTEM RECOVERY:**
- **Container Restart**: Auto-restarts after system reboot
- **Service Recovery**: pveproxy auto-enabled and started
- **Health Monitoring**: `/health` endpoint for status checks
- **Log Access**: `docker-compose logs -f mcp-server`

### **🚨 TROUBLESHOOTING GUIDE:**

**Common Issues & Solutions:**

1. **MCP Connection Fails (HTTP 404)**
   - **Check**: Using correct endpoint `/api/mcp` (not `/api`)
   - **Fix**: `claude mcp remove proxmox-production && claude mcp add --transport http proxmox-production http://IP:8080/api/mcp`

2. **execute_command Not Working**
   - **Check**: SSH key permissions in container
   - **Fix**: `cd /opt/proxmox-mcp && sudo chown -R 1000:1000 keys/`

3. **Container Not Starting**
   - **Check**: Docker service running, .env file exists
   - **Fix**: `sudo systemctl start docker && cd docker && sudo ./install.sh`

4. **Port 8080 Not Accessible**
   - **Check**: Firewall rules, container binding
   - **Fix**: `sudo ufw allow 8080/tcp && docker-compose restart`

5. **SSH Authentication Fails**
   - **Check**: claude-user exists, SSH key deployed
   - **Fix**: Re-run install.sh user setup phase

**Validation Commands:**
```bash
# Test MCP server health
curl -f http://localhost:8080/health

# Test container status  
cd /opt/proxmox-mcp/docker && docker-compose ps

# Test SSH key access
ssh -i /opt/proxmox-mcp/keys/ssh_key claude-user@localhost whoami

# Test MCP connection
claude mcp list
```

### **COORDINATION REQUIREMENTS:**
- **Security Agent** must validate all permission changes
- **DevOps Agent** must ensure deployment reliability
- **Documentation Agent** must create user-friendly guides
- **Architecture Agent** must maintain system design integrity
- **Integration Agent** must ensure MCP protocol compliance

---

## ⚠️ **IMPORTANT CONSTRAINTS**

### **SECURITY REQUIREMENTS:**
- **Never compromise** existing system security
- **Always validate** permission changes thoroughly
- **Document all security implications** of changes
- **Maintain audit trails** for all administrative actions
- **Test security restrictions** before deployment

### **OPERATIONAL REQUIREMENTS:**
- **Maintain system uptime** during all changes
- **Provide rollback procedures** for all modifications
- **Test in isolated environment** before production
- **Document all procedures** for future maintenance
- **Ensure user experience** remains simple and intuitive

### **COMMUNICATION REQUIREMENTS:**
- **Clear progress updates** using TodoWrite/TodoRead
- **Comprehensive documentation** for all deliverables
- **Risk assessment** for all significant changes
- **User-focused** communication and documentation
- **Technical accuracy** in all recommendations

---

## 🔧 **IMPLEMENTATION APPROACH**

### **CURRENT PROJECT STATUS:**
- **Existing Docker Infrastructure**: Comprehensive docker-compose setup exists
- **Container Not Running**: Deployment issues preventing container startup
- **Security Issues**: claude-user has excessive privileges
- **No Simple Installation**: Complex setup process for users
- **GitHub Actions Broken**: Manual deployment required

### **AGENT DEPLOYMENT STRATEGY:**
```yaml
Parallel Workstreams:
  Security Agent:
    - Analyze current claude-user permissions
    - Design restricted permission model
    - Create validation procedures
    - Document security implications
    
  DevOps Agent:
    - Investigate container deployment issues
    - Create installation automation
    - Design update mechanisms
    - Develop testing procedures
    
  Documentation Agent:
    - Create user installation guides
    - Document troubleshooting procedures
    - Maintain system architecture docs
    - Update configuration examples
    
  Integration Agent:
    - Ensure MCP protocol compliance
    - Validate container networking
    - Test client connectivity
    - Verify API functionality
```

---

**🎯 PROJECT MANAGER CLAUDE READY FOR COORDINATED AGENT DEPLOYMENT**

*This configuration establishes Claude as the project manager with clear guidelines for deploying specialized agents in parallel to accelerate project delivery while maintaining quality and security standards.*