# Proxmox MCP Server - Requirements Document

## 1. Project Overview

The Proxmox MCP (Model Context Protocol) Server provides LLM clients with comprehensive command-line access to Proxmox Virtual Environment hosts while maintaining security guardrails. The server runs as a Docker container on the Proxmox node and exposes terminal capabilities through the MCP protocol, acting as an intelligent extension for Proxmox administration.

## 2. Core Functionality Requirements

### 2.1 Terminal Access
- **Full Command Line Interface**: Execute arbitrary shell commands on the Proxmox host
- **Persistent Sessions**: Maintain shell state with 30-minute inactivity timeout
- **Command Execution**: Support both quick commands and complex multi-step operations
- **Output Handling**: Return combined stdout/stderr with chronological ordering and prefixes
- **Timeout Management**: Default 60-second timeout, client-configurable up to 300 seconds

### 2.2 Proxmox-Specific Operations
- **Container Management**: Start, stop, restart, delete containers
- **VM Operations**: Create, configure, start, stop, delete virtual machines
- **User Management**: Create users, modify passwords, manage permissions
- **Storage Operations**: Manage storage pools, volumes, backups
- **Network Configuration**: VLAN setup, bridge configuration, firewall rules
- **System Information**: Read access to node status, resource usage, configuration
- **Discovery**: Automatic enumeration of running containers and VMs across all nodes
- **Docker Visibility**: List all Docker containers running across the cluster
- **Template Management**: Download, upload, and manage VM/container templates

### 2.3 Safety Mechanisms

#### 2.3.1 Prohibited Operations (Minimal Restrictions)
- **Root User Protection**: Cannot modify root user password or delete root account
- **Node Destruction**: Cannot delete or permanently destroy the main Proxmox node
- **Critical System Files**: Cannot delete essential system binaries in `/usr/bin`, `/usr/sbin`
- **Boot Configuration**: Cannot delete `/boot` directory contents (modifications allowed)

#### 2.3.2 Operation Modes
- **Normal Mode** (default): Full administrative access with minimal safety guardrails
- **Safe Mode**: Additional confirmation prompts for destructive operations
- **Mode Toggle**: Runtime switching between modes via MCP commands

#### 2.3.3 User Management Capabilities
- **User Creation**: Create new Proxmox users with appropriate permissions
- **Password Management**: Change passwords for non-root users
- **Permission Assignment**: Assign roles and privileges to users
- **Group Management**: Create and manage user groups
- **Authentication**: Configure 2FA, API tokens, SSH keys for users

#### 2.3.4 Beginner-Friendly Features
- **Command Explanation**: Provide context for what commands will do before execution
- **Best Practice Guidance**: Suggest optimal configurations and approaches
- **Error Recovery**: Help diagnose and fix common Proxmox issues
- **Documentation Access**: Quick access to relevant Proxmox documentation snippets

## 3. Docker Container Specifications

### 3.1 Base Requirements
- **Base Image**: Ubuntu 22.04 LTS (for full compatibility with Proxmox tools)
- **Runtime User**: Dedicated `proxmox-mcp` user with sudo privileges
- **Working Directory**: `/opt/proxmox-mcp`
- **Network**: Host network access to communicate with Proxmox services

### 3.2 Container Capabilities
- **Privileged Operations**: Near-full sudo access (excluding root user modifications)
- **Volume Mounts**: 
  - Read-write access to Proxmox configuration directories
  - Access to storage pool directories
  - Log directories for audit trails
- **Resource Limits**: Configurable CPU/memory constraints

### 3.3 Installation via Git
```bash
# Installation command structure
git clone https://github.com/user/proxmox-mcp.git
cd proxmox-mcp
docker-compose up -d
```

### 3.4 Version Management
- **Tagged Releases**: Semantic versioning (v1.0.0, v1.1.0, etc.)
- **Update Process**: `git pull && docker-compose up -d --build`
- **Rollback Support**: Ability to checkout specific version tags
- **Configuration Persistence**: Settings maintained across updates

## 4. Authentication Flow Design

### 4.1 Initial Setup Process
1. **Container Startup**: Generate unique MCP server identifier
2. **Proxmox Integration**: Auto-detect Proxmox installation and create API user
3. **API Token Creation**: Generate Proxmox API token for MCP operations
4. **Client Registration**: First-time client connection requires authentication
5. **Permission Verification**: Confirm MCP user has necessary privileges

### 4.2 Authentication Methods
- **Primary**: Proxmox API token-based authentication
- **Secondary**: Container-generated shared secret for MCP protocol
- **Per-Client**: Individual authentication tokens for each MCP client
- **Fallback**: Direct system authentication for critical operations

### 4.3 Security Features
- **Token Rotation**: Periodic refresh of authentication credentials
- **Session Management**: Secure session handling with automatic cleanup
- **Access Logging**: All authentication attempts logged for audit
- **Privilege Escalation**: Secure sudo access for administrative operations

## 5. API Endpoint Definitions

### 5.1 Core MCP Tools
```
proxmox/execute_command
  - command: string (shell command to execute)
  - timeout: number (optional, max 300 seconds)
  - mode: "normal" | "safe" (execution mode)
  - explain: boolean (provide explanation before execution)

proxmox/list_containers
  - node: string (optional, specific node)
  - status: "running" | "stopped" | "all" (optional filter)

proxmox/container_action
  - container_id: string
  - action: "start" | "stop" | "restart" | "delete" | "create"
  - config: object (optional, for create operations)

proxmox/vm_management
  - vm_id: string
  - action: "start" | "stop" | "restart" | "delete" | "create" | "clone"
  - config: object (optional, for create/modify operations)

proxmox/user_management
  - action: "create" | "delete" | "modify" | "list"
  - username: string
  - password: string (optional)
  - permissions: array (optional)

proxmox/get_system_info
  - include_resources: boolean (CPU, memory, storage usage)
  - include_network: boolean (network configuration)
  - include_storage: boolean (storage pool information)

proxmox/storage_operations
  - action: "list" | "create" | "delete" | "backup" | "restore"
  - storage_id: string (optional)
  - config: object (optional)

proxmox/network_config
  - action: "list" | "create" | "modify" | "delete"
  - interface: string (optional)
  - config: object (optional)

proxmox/get_command_history
  - days: number (1-7, default 1)
  - filter: string (optional command filter)

proxmox/toggle_mode
  - mode: "normal" | "safe"

proxmox/explain_command
  - command: string (command to explain)
  - context: string (optional, current situation context)

proxmox/best_practices
  - topic: string (area of Proxmox to get guidance on)

proxmox/help_llm
  - query: string (optional, specific information requested)
  - category: "installation" | "version" | "update" | "config" | "status" | "all"

proxmox/get_mcp_info
  - include_system: boolean (system information)
  - include_git: boolean (git repository status)
  - include_config: boolean (current configuration)

proxmox/check_updates
  - check_remote: boolean (check git repository for updates)
  - include_changelog: boolean (show what's new)

proxmox/self_update
  - version: string (optional, specific version to update to)
  - backup_config: boolean (default true)
  - restart_after: boolean (default true)

proxmox/get_changelog
  - from_version: string (optional, show changes from specific version)
  - to_version: string (optional, show changes up to specific version)

proxmox/backup_config
  - backup_name: string (optional, custom backup name)
  - include_logs: boolean (backup audit logs too)

proxmox/restore_config
  - backup_name: string (backup to restore from)
  - restart_after: boolean (restart MCP after restore)

proxmox/health_check
  - deep_check: boolean (comprehensive system check)
  - fix_issues: boolean (attempt to fix detected problems)
```

### 5.2 Response Formats
```json
{
  "success": boolean,
  "data": object,
  "stdout": string,
  "stderr": string,
  "execution_time": number,
  "timestamp": string,
  "mode": string,
  "explanation": string,
  "warnings": array,
  "suggestions": array
}
```

### 5.3 MCP Self-Help Tool Details

#### proxmox/help_llm Response Format:
```json
{
  "success": true,
  "data": {
    "installation": {
      "path": "/opt/proxmox-mcp",
      "installed_date": "2025-01-15T10:30:00Z",
      "installation_method": "git_clone",
      "docker_image": "proxmox-mcp:v1.2.3"
    },
    "version": {
      "current": "v1.2.3",
      "commit_hash": "abc123def456",
      "build_date": "2025-01-10T14:20:00Z",
      "branch": "main"
    },
    "git_status": {
      "remote_url": "https://github.com/user/proxmox-mcp.git",
      "latest_remote": "v1.3.0",
      "updates_available": true,
      "commits_behind": 5,
      "local_changes": false
    },
    "update_info": {
      "update_command": "cd /opt/proxmox-mcp && git pull && docker-compose up -d --build",
      "backup_location": "/opt/proxmox-mcp/backups",
      "last_update": "2025-01-10T14:20:00Z"
    },
    "configuration": {
      "config_file": "/opt/proxmox-mcp/.env",
      "log_level": "INFO",
      "audit_retention": "7 days",
      "current_mode": "normal",
      "mcp_port": 3001
    },
    "status": {
      "container_status": "running",
      "uptime": "5 days, 3 hours",
      "mcp_clients_connected": 1,
      "last_command": "2025-01-15T09:45:00Z",
      "health": "healthy"
    }
  }
}
```

#### Information Categories:

**Installation Information:**
- Current installation path
- Installation date and method
- Docker container details
- Volume mounts and permissions

**Version Information:**
- Current version tag
- Git commit hash
- Build timestamp
- Current branch

**Update Information:**
- Latest available version
- Commits behind remote
- Local modifications status
- Update procedure commands
- Rollback options

**Configuration Details:**
- Current settings
- Config file locations
- Runtime parameters
- Mode settings

**System Status:**
- Container health
- Uptime statistics
- Connected clients
- Resource usage
- Recent activity

#### Example LLM Usage Scenarios:

1. **Version Check**: "What version of the MCP am I running?"
2. **Update Check**: "Are there any updates available?"
3. **Installation Info**: "Where is the MCP installed and how was it set up?"
4. **Configuration Review**: "What are my current MCP settings?"
5. **Health Status**: "Is the MCP running properly?"
6. **Update Process**: "How do I update to the latest version?"

## 6. Safety Mechanisms

### 6.1 Command Filtering (Minimal)
- **Critical Protection**: Only block commands that could destroy root user or main node
- **Warning System**: Alert before potentially destructive operations
- **Confirmation Prompts**: In safe mode, require confirmation for major changes
- **Explanation Mode**: Provide detailed explanations of command consequences

### 6.2 Audit & Logging
- **Command History**: 7-day retention of all executed commands
- **Audit Trail**: User, timestamp, command, result, mode for each operation
- **Change Tracking**: Log all configuration changes with before/after states
- **Log Rotation**: Automatic cleanup of old audit logs
- **Export Capability**: Audit log retrieval via MCP tools

### 6.3 Beginner Safety Features
- **Command Explanation**: Automatic explanation of complex commands
- **Undo Suggestions**: Where possible, provide commands to reverse changes
- **Best Practice Alerts**: Warn when deviating from recommended configurations
- **Resource Impact**: Show expected resource usage for operations

## 7. Installation Procedures

### 7.1 Prerequisites
- Docker and Docker Compose installed on Proxmox host
- Git available on the system
- Network connectivity for container registry access
- Proxmox VE 7.0+ installation

### 7.2 Installation Steps
```bash
# 1. Clone repository
git clone https://github.com/user/proxmox-mcp.git /opt/proxmox-mcp
cd /opt/proxmox-mcp

# 2. Configure environment
cp .env.example .env
nano .env  # Edit configuration as needed

# 3. Run setup script (creates MCP user, sets permissions)
./setup.sh

# 4. Deploy container
docker-compose up -d

# 5. Verify installation
docker-compose logs -f proxmox-mcp

# 6. Test MCP connection
# (Configuration details for MCP client)
```

### 7.3 Configuration Options
- **MCP Server Port**: Default 3001, configurable
- **Authentication Settings**: Token expiration, rotation schedule
- **Safety Settings**: Command timeout defaults, mode preferences
- **Logging Configuration**: Audit retention, log levels
- **Explanation Mode**: Default verbosity for command explanations

### 7.4 Update Procedure
```bash
cd /opt/proxmox-mcp
git pull origin main
docker-compose down
docker-compose up -d --build
```

## 8. Technical Architecture

### 8.1 Container Structure
```
/opt/proxmox-mcp/
├── src/                 # MCP server implementation
├── config/              # Configuration files
├── logs/                # Audit and application logs
├── scripts/             # Helper scripts and setup tools
├── docs/                # Proxmox command reference and guides
├── docker-compose.yml   # Container orchestration
├── Dockerfile          # Container build instructions
├── setup.sh            # Initial setup script
└── README.md           # Setup and usage documentation
```

### 8.2 Integration Points
- **Proxmox API**: REST API integration for system operations
- **Shell Interface**: Direct command execution with full privileges
- **MCP Protocol**: Standard MCP server implementation
- **Logging System**: Structured logging with rotation
- **Documentation Engine**: Built-in help and explanation system

### 8.3 Monitoring & Health Checks
- **Container Health**: Docker health check endpoints
- **Service Status**: MCP server availability monitoring
- **Resource Usage**: CPU, memory, and disk utilization tracking
- **Connection Status**: Active MCP client connection monitoring
- **Proxmox Health**: Monitor Proxmox service status and cluster health

### 8.4 Beginner-Friendly Features
- **Interactive Guidance**: Step-by-step assistance for common tasks
- **Command Builder**: Help construct complex Proxmox commands
- **Error Diagnosis**: Automatic analysis and solutions for common errors
- **Learning Mode**: Educational explanations alongside command execution

---

This requirements document provides the foundation for implementing a secure, feature-rich Proxmox MCP server that balances powerful terminal access with necessary safety guardrails, while maintaining self-awareness and beginner-friendly features for comprehensive Proxmox administration.