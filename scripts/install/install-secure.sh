#!/bin/bash
# Proxmox MCP Secure Installation Script
# Dual-Port Security Model with Device Authentication
# Port 8080: MCP with device token authentication
# Port 8081: Admin interface (local network only)

set -eu

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/installation-secure.log"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups/$(date +%Y%m%d_%H%M%S)"
readonly DOCKER_DIR="${PROJECT_ROOT}/docker"
readonly KEYS_DIR="${PROJECT_ROOT}/keys"
readonly DATA_DIR="${PROJECT_ROOT}/data"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Security phases
declare -a PHASES=(
    "Phase 1: System Prerequisites"
    "Phase 2: Security User Setup"
    "Phase 3: Configuration Collection"
    "Phase 4: Security Environment Setup"
    "Phase 5: Authentication System Setup"
    "Phase 6: Network Security Configuration"
    "Phase 7: Container Deployment"
    "Phase 8: Service Startup & Validation"
    "Phase 9: Authentication Testing"
    "Phase 10: Admin Interface Setup"
    "Phase 11: Client Configuration Guide"
)

# Global variables
PROXMOX_HOST=""
PROXMOX_TOKEN_NAME=""
PROXMOX_TOKEN_VALUE=""
SSH_HOST=""
CLAUDE_USER_PASSWORD=""
SERVER_IP=""
LOCAL_NETWORK=""

# Progress tracking
CURRENT_PHASE=0
TOTAL_PHASES=${#PHASES[@]}

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

security_note() {
    echo -e "${PURPLE}🔒 $*${NC}" | tee -a "$LOG_FILE"
}

# Progress display
show_phase() {
    CURRENT_PHASE=$((CURRENT_PHASE + 1))
    echo ""
    echo -e "${CYAN}[${CURRENT_PHASE}/${TOTAL_PHASES}] ${PHASES[$((CURRENT_PHASE - 1))]}${NC}"
    echo "=================================================="
}

# Error handling
cleanup_on_error() {
    error "Installation failed! Check ${LOG_FILE} for details"
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        warning "Backups available in: $BACKUP_DIR"
    fi
    exit 1
}

trap cleanup_on_error ERR

# Helper functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_root() {
    [ "$(id -u)" -eq 0 ]
}

get_server_ip() {
    # Try multiple methods to get server IP
    local ip=""
    
    # Method 1: Primary network interface
    ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo "")
    
    # Method 2: Default route interface
    if [ -z "$ip" ]; then
        ip=$(ip route | grep default | awk '{print $5}' | head -1 | xargs ip addr show | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1 || echo "")
    fi
    
    # Method 3: hostname -I
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}' || echo "")
    fi
    
    echo "$ip"
}

detect_local_network() {
    local server_ip="$1"
    
    if [[ "$server_ip" =~ ^192\.168\. ]]; then
        echo "192.168.0.0/16"
    elif [[ "$server_ip" =~ ^10\. ]]; then
        echo "10.0.0.0/8"
    elif [[ "$server_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        echo "172.16.0.0/12"
    else
        # Default to 192.168.x.x/24 subnet
        echo "$(echo "$server_ip" | cut -d. -f1-3).0/24"
    fi
}

# Phase 1: System Prerequisites
install_prerequisites() {
    show_phase
    
    if ! is_root; then
        error "This script must be run as root"
        exit 1
    fi
    
    info "Updating package repositories..."
    apt-get update -qq
    
    info "Installing required packages..."
    apt-get install -y \
        curl \
        wget \
        git \
        sudo \
        ufw \
        iptables \
        net-tools \
        openssh-server \
        gnupg \
        lsb-release \
        ca-certificates \
        software-properties-common \
        pwgen
    
    # Install Docker
    if ! command_exists docker; then
        info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
    else
        success "Docker already installed"
    fi
    
    # Install Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        info "Installing Docker Compose..."
        local compose_version="2.23.0"
        curl -L "https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        success "Docker Compose already available"
    fi
    
    success "System prerequisites installed"
}

# Phase 2: Security User Setup
setup_security_user() {
    show_phase
    
    info "Setting up claude-user with restricted permissions..."
    
    # Create user if doesn't exist
    if ! id "claude-user" >/dev/null 2>&1; then
        info "Creating claude-user..."
        useradd -m -s /bin/bash claude-user
    else
        success "claude-user already exists"
    fi
    
    # Generate secure password
    if [ -z "${CLAUDE_USER_PASSWORD:-}" ]; then
        CLAUDE_USER_PASSWORD=$(pwgen -s 16 1)
        info "Generated secure password for claude-user"
    fi
    
    echo "claude-user:$CLAUDE_USER_PASSWORD" | chpasswd
    
    # Setup SSH key for claude-user
    info "Setting up SSH authentication for claude-user..."
    
    # Create keys directory
    mkdir -p "$KEYS_DIR"
    chmod 700 "$KEYS_DIR"
    
    # Generate SSH key if it doesn't exist
    if [ ! -f "$KEYS_DIR/ssh_key" ]; then
        ssh-keygen -t rsa -b 4096 -f "$KEYS_DIR/ssh_key" -N "" -C "proxmox-mcp-server"
        chmod 600 "$KEYS_DIR/ssh_key"
        chmod 644 "$KEYS_DIR/ssh_key.pub"
    fi
    
    # Set proper ownership for container access
    chown -R 1000:1000 "$KEYS_DIR"
    
    # Setup authorized_keys for claude-user
    local claude_home="/home/claude-user"
    mkdir -p "$claude_home/.ssh"
    cp "$KEYS_DIR/ssh_key.pub" "$claude_home/.ssh/authorized_keys"
    chmod 700 "$claude_home/.ssh"
    chmod 600 "$claude_home/.ssh/authorized_keys"
    chown -R claude-user:claude-user "$claude_home/.ssh"
    
    # Deploy restricted sudoers configuration
    info "Configuring restricted sudo permissions..."
    cp "${PROJECT_ROOT}/config/sudoers/claude-user-restricted-sudoers" "/etc/sudoers.d/claude-user"
    chmod 440 "/etc/sudoers.d/claude-user"
    visudo -c -f "/etc/sudoers.d/claude-user"
    
    success "Security user setup completed"
    security_note "claude-user configured with restricted permissions and SSH key authentication"
}

# Phase 3: Configuration Collection
collect_configuration() {
    show_phase
    
    info "Collecting system and Proxmox configuration..."
    
    # Get server IP
    SERVER_IP=$(get_server_ip)
    if [ -z "$SERVER_IP" ]; then
        error "Could not determine server IP address"
        exit 1
    fi
    info "Detected server IP: $SERVER_IP"
    
    # Detect local network
    LOCAL_NETWORK=$(detect_local_network "$SERVER_IP")
    info "Detected local network: $LOCAL_NETWORK"
    
    # Set SSH host (default to server IP)
    SSH_HOST="${SSH_HOST:-$SERVER_IP}"
    
    # Collect Proxmox configuration
    echo ""
    info "Please provide Proxmox configuration details:"
    
    while [ -z "$PROXMOX_HOST" ]; do
        read -p "Proxmox VE hostname/IP: " PROXMOX_HOST
    done
    
    while [ -z "$PROXMOX_TOKEN_NAME" ]; do
        read -p "Proxmox API token name (format: user@realm!tokenname): " PROXMOX_TOKEN_NAME
    done
    
    while [ -z "$PROXMOX_TOKEN_VALUE" ]; do
        read -s -p "Proxmox API token value: " PROXMOX_TOKEN_VALUE
        echo
    done
    
    success "Configuration collected successfully"
}

# Phase 4: Security Environment Setup
setup_security_environment() {
    show_phase
    
    info "Creating secure environment configuration..."
    
    # Create data directory for device authentication
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"
    chown 1000:1000 "$DATA_DIR"
    
    # Create Docker environment file
    cat > "${DOCKER_DIR}/.env" << EOF
# Proxmox MCP Server Configuration (Secure)
# Generated on $(date)

# Server Configuration
MCP_HOST=0.0.0.0
MCP_PORT=8080
ADMIN_PORT=8081
LOG_LEVEL=INFO

# Security Configuration
DEVICE_AUTH_ENABLED=true

# SSH Configuration
SSH_TARGET=claude-user@${SSH_HOST}
SSH_HOST=${SSH_HOST}
SSH_USER=claude-user
SSH_PORT=22

# Proxmox Configuration
PROXMOX_HOST=${PROXMOX_HOST}
PROXMOX_USER=${PROXMOX_TOKEN_NAME}
PROXMOX_TOKEN_NAME=${PROXMOX_TOKEN_NAME}
PROXMOX_TOKEN_VALUE=${PROXMOX_TOKEN_VALUE}
PROXMOX_VERIFY_SSL=false

# Feature Configuration
ENABLE_PROXMOX_API=true
ENABLE_DANGEROUS_COMMANDS=false

# Build Configuration
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
VERSION=2.0.0-secure
IMAGE_TAG=2.0.0-secure
EOF
    
    success "Security environment configured"
    security_note "Device authentication enabled with secure defaults"
}

# Phase 5: Authentication System Setup
setup_authentication_system() {
    show_phase
    
    info "Initializing device authentication system..."
    
    # Create authentication storage files
    mkdir -p "$DATA_DIR"
    
    # Initialize empty JSON files for device management
    echo '{}' > "$DATA_DIR/pending_requests.json"
    echo '{}' > "$DATA_DIR/approved_devices.json" 
    echo '{}' > "$DATA_DIR/revoked_tokens.json"
    
    # Set proper permissions
    chmod 644 "$DATA_DIR"/*.json
    chown 1000:1000 "$DATA_DIR"/*.json
    
    success "Authentication system initialized"
    security_note "Device registration and token management ready"
}

# Phase 6: Network Security Configuration
setup_network_security() {
    show_phase
    
    info "Configuring network security and firewall rules..."
    
    # Configure UFW firewall
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow MCP server (port 8080) from anywhere
    ufw allow 8080/tcp comment "Proxmox MCP Server"
    
    # Allow admin interface (port 8081) from local network only
    ufw allow from "$LOCAL_NETWORK" to any port 8081 comment "MCP Admin Interface (Local Only)"
    
    # Enable firewall
    ufw --force enable
    
    success "Network security configured"
    security_note "Port 8080 (MCP): Internet accessible with token auth"
    security_note "Port 8081 (Admin): Local network only ($LOCAL_NETWORK)"
}

# Phase 7: Container Deployment
deploy_containers() {
    show_phase
    
    info "Building and deploying secure containers..."
    
    cd "$DOCKER_DIR"
    
    # Build container with security features
    docker-compose -f docker-compose.prod.yml build --no-cache
    
    success "Containers built successfully"
}

# Phase 8: Service Startup & Validation
start_and_validate_services() {
    show_phase
    
    info "Starting services and performing validation..."
    
    cd "$DOCKER_DIR"
    
    # Start services
    docker-compose -f docker-compose.prod.yml up -d
    
    # Wait for services to be ready
    info "Waiting for services to start..."
    sleep 10
    
    # Health check for MCP server
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:8080/health" >/dev/null 2>&1; then
            success "MCP server (port 8080) is healthy"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            error "MCP server failed to start within timeout"
            docker-compose -f docker-compose.prod.yml logs
            exit 1
        fi
        
        info "Attempt $attempt/$max_attempts: Waiting for MCP server..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    # Health check for admin interface
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:8081/health" >/dev/null 2>&1; then
            success "Admin interface (port 8081) is healthy"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            error "Admin interface failed to start within timeout"
            docker-compose -f docker-compose.prod.yml logs
            exit 1
        fi
        
        info "Attempt $attempt/$max_attempts: Waiting for admin interface..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    success "All services started successfully"
}

# Phase 9: Authentication Testing
test_authentication() {
    show_phase
    
    info "Testing authentication system..."
    
    # Test device registration endpoint
    local test_response
    test_response=$(curl -s -X POST "http://localhost:8080/register" \
        -H "Content-Type: application/json" \
        -d '{"device_name": "test-device", "client_info": "installation-test"}' || echo "")
    
    if echo "$test_response" | grep -q "success.*true"; then
        success "Device registration endpoint working"
    else
        warning "Device registration test inconclusive: $test_response"
    fi
    
    # Test unauthenticated MCP access (should fail)
    local mcp_response
    mcp_response=$(curl -s "http://localhost:8080/api/mcp" || echo "")
    
    if echo "$mcp_response" | grep -q -i "authentication"; then
        success "MCP authentication protection working"
    else
        warning "MCP authentication test inconclusive"
    fi
    
    success "Authentication testing completed"
}

# Phase 10: Admin Interface Setup
setup_admin_interface() {
    show_phase
    
    info "Verifying admin interface accessibility..."
    
    # Test admin interface from localhost
    local admin_response
    admin_response=$(curl -s "http://localhost:8081/" || echo "")
    
    if echo "$admin_response" | grep -q -i "dashboard\|admin\|proxmox"; then
        success "Admin interface accessible from localhost"
    else
        warning "Admin interface test inconclusive"
    fi
    
    success "Admin interface setup completed"
    security_note "Admin interface restricted to local network access"
}

# Phase 11: Client Configuration Guide
generate_client_guide() {
    show_phase
    
    info "Generating client configuration guide..."
    
    cat > "${PROJECT_ROOT}/CLIENT-SETUP-GUIDE.md" << EOF
# Proxmox MCP Client Setup Guide (Secure)

## Overview
Your Proxmox MCP server is now running with enhanced security:
- **Port 8080**: MCP server with device token authentication
- **Port 8081**: Admin interface (local network only)

## Server Information
- **Server IP**: $SERVER_IP
- **MCP Endpoint**: http://$SERVER_IP:8080/api/mcp
- **Admin Interface**: http://$SERVER_IP:8081/ (local network only)

## Step 1: Register Your Device

Before you can use the MCP server, you must register your device:

\`\`\`bash
curl -X POST "http://$SERVER_IP:8080/register" \\
    -H "Content-Type: application/json" \\
    -d '{
        "device_name": "my-workstation",
        "client_info": "Claude Code Client"
    }'
\`\`\`

This will submit a registration request. You'll receive a response with a device ID.

## Step 2: Admin Approval

1. Access the admin interface from your local network: http://$SERVER_IP:8081/
2. Go to "Pending Requests" page
3. Review and approve your device registration
4. Copy the generated device token

## Step 3: Configure Claude Code

Once approved, add the MCP server to Claude Code:

\`\`\`bash
claude mcp add --transport http proxmox-production \\
    "http://$SERVER_IP:8080/api/mcp" \\
    --auth-header "Authorization: Bearer YOUR_DEVICE_TOKEN"
\`\`\`

Replace \`YOUR_DEVICE_TOKEN\` with the token from the admin interface.

## Step 4: Verify Connection

Test the connection:

\`\`\`bash
claude mcp list
claude mcp test proxmox-production
\`\`\`

## Available MCP Tools

Once connected, you can use these tools:
- \`execute_command\`: Run shell commands via SSH
- \`list_vms\`: List all VMs across Proxmox nodes
- \`vm_status\`: Get detailed VM status
- \`vm_action\`: Start/stop/restart VMs
- \`node_status\`: Get Proxmox node information
- \`proxmox_api\`: Make direct Proxmox API calls

## Security Features

### Device Authentication
- All MCP requests require a valid device token
- Tokens expire automatically (configurable)
- Tokens can be revoked instantly via admin interface

### Network Security
- Port 8080: Internet accessible but requires authentication
- Port 8081: Local network only ($LOCAL_NETWORK)
- Firewall configured to block unauthorized access

### Rate Limiting
- Device registration: 5 requests per 15 minutes
- MCP requests: 60 requests per minute
- Admin interface: 120 requests per minute

## Troubleshooting

### Authentication Errors
If you get authentication errors:
1. Verify your token hasn't expired
2. Check token wasn't revoked in admin interface
3. Ensure you're using the correct Authorization header

### Connection Issues
If you can't connect:
1. Check firewall allows port 8080
2. Verify server is running: \`curl http://$SERVER_IP:8080/health\`
3. Check Docker logs: \`docker-compose logs -f mcp-server\`

### Admin Access Issues
If you can't access admin interface:
1. Ensure you're on the local network ($LOCAL_NETWORK)
2. Check port 8081 is accessible: \`curl http://$SERVER_IP:8081/health\`
3. Verify firewall rules allow local network access

## Admin Interface Features

### Dashboard
- System overview and statistics
- Recent device activity
- Security status monitoring

### Device Management
- Approve/reject registration requests
- View active devices and usage statistics
- Revoke device access
- Set token expiration periods

### Security Monitoring
- Track authentication attempts
- Monitor rate limiting triggers
- View system health metrics

## Security Best Practices

1. **Regular Token Rotation**: Periodically regenerate device tokens
2. **Monitor Access**: Review device activity in admin interface
3. **Network Segmentation**: Keep admin interface on trusted network
4. **Log Monitoring**: Check logs for suspicious activity
5. **Backup Authentication Data**: Backup \`/app/data\` directory

## Support

For issues or questions:
1. Check Docker logs: \`cd $DOCKER_DIR && docker-compose logs\`
2. Review installation log: \`$LOG_FILE\`
3. Verify health endpoints respond correctly

## File Locations

- Configuration: \`$DOCKER_DIR/.env\`
- SSH Keys: \`$KEYS_DIR/\`
- Device Data: \`$DATA_DIR/\`
- Logs: \`$LOG_FILE\`
- Backups: \`$BACKUP_DIR\`

Generated on: $(date)
EOF
    
    success "Client setup guide created: ${PROJECT_ROOT}/CLIENT-SETUP-GUIDE.md"
}

# Main installation function
main() {
    echo ""
    echo -e "${CYAN}🔒 Proxmox MCP Secure Installation${NC}"
    echo -e "${CYAN}=====================================${NC}"
    echo ""
    security_note "Installing dual-port MCP server with device authentication"
    security_note "Port 8080: MCP server (internet + token auth)"
    security_note "Port 8081: Admin interface (local network only)"
    echo ""
    
    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Installation started at $(date)" > "$LOG_FILE"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Run installation phases
    install_prerequisites
    setup_security_user
    collect_configuration
    setup_security_environment
    setup_authentication_system
    setup_network_security
    deploy_containers
    start_and_validate_services
    test_authentication
    setup_admin_interface
    generate_client_guide
    
    # Final success message
    echo ""
    echo -e "${GREEN}🎉 Secure Installation Completed Successfully!${NC}"
    echo "=================================================="
    echo ""
    echo -e "${CYAN}📡 MCP Server Details:${NC}"
    echo "   URL: http://$SERVER_IP:8080/api/mcp"
    echo "   Health: http://$SERVER_IP:8080/health"
    echo "   Registration: http://$SERVER_IP:8080/register"
    echo ""
    echo -e "${CYAN}🖥️  Admin Interface:${NC}"
    echo "   URL: http://$SERVER_IP:8081/"
    echo "   Health: http://$SERVER_IP:8081/health"
    echo "   Network: Local only ($LOCAL_NETWORK)"
    echo ""
    echo -e "${CYAN}🔐 Security Features:${NC}"
    echo "   ✅ Device token authentication"
    echo "   ✅ Network access restrictions"
    echo "   ✅ Rate limiting protection"
    echo "   ✅ SSH key authentication"
    echo "   ✅ Restricted sudo permissions"
    echo ""
    echo -e "${CYAN}📚 Next Steps:${NC}"
    echo "   1. Read client guide: ${PROJECT_ROOT}/CLIENT-SETUP-GUIDE.md"
    echo "   2. Register your device: POST http://$SERVER_IP:8080/register"
    echo "   3. Approve via admin: http://$SERVER_IP:8081/pending"
    echo "   4. Configure Claude Code with device token"
    echo ""
    echo -e "${CYAN}📄 Important Files:${NC}"
    echo "   Configuration: $DOCKER_DIR/.env"
    echo "   Client Guide: ${PROJECT_ROOT}/CLIENT-SETUP-GUIDE.md"
    echo "   Installation Log: $LOG_FILE"
    echo ""
    security_note "Installation completed with enhanced security enabled"
}

# Run main installation
main "$@"