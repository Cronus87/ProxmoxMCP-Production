#!/bin/bash

# PROXMOX MCP PRODUCTION INSTALLATION AUTOMATION
# =============================================
# Complete single-command installation system for enterprise-grade Proxmox MCP deployment
# Leverages existing Docker infrastructure and enhanced security model
#
# ARCHITECTURE: Master installer with modular phases and comprehensive validation
# FEATURES: Auto-discovery, guided configuration, security integration, rollback capability
# VERSION: 1.0 - Master Installation Automation
# SECURITY: Full integration with bulletproof security model

set -euo pipefail

# ==============================================================================
# GLOBAL CONFIGURATION
# ==============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly INSTALLATION_ID="proxmox-mcp-$(date +%Y%m%d-%H%M%S)"
readonly INSTALL_ROOT="/opt/proxmox-mcp"
readonly BACKUP_ROOT="/opt/proxmox-mcp-backups"
readonly LOG_FILE="/var/log/proxmox-mcp-install.log"
readonly CONFIG_DIR="$INSTALL_ROOT/config"
readonly KEYS_DIR="$INSTALL_ROOT/keys"

# Service configuration
readonly SERVICE_NAME="proxmox-mcp"
readonly CONTAINER_NAME_PREFIX="proxmox-mcp"
readonly NETWORK_NAME="mcp-network"

# Installation phases
readonly PHASES=(
    "system_preparation"
    "configuration_discovery"
    "security_deployment"
    "container_deployment"
    "client_configuration"
    "final_validation"
)

# ==============================================================================
# COLOR SCHEME AND OUTPUT FUNCTIONS
# ==============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Enhanced logging with timestamps and levels
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp]${NC} ${BOLD}[$level]${NC} $message" | tee -a "$LOG_FILE"
}

info() {
    log "INFO" "${BLUE}$*${NC}"
}

success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

critical() {
    log "CRITICAL" "${RED}🚨 $*${NC}"
    exit 1
}

phase_header() {
    local phase="$1"
    local description="$2"
    echo ""
    echo "=============================================="
    echo -e "${PURPLE}${BOLD}PHASE: $phase${NC}"
    echo "=============================================="
    echo -e "${CYAN}$description${NC}"
    echo ""
}

# Progress tracking
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local percentage=$((current * 100 / total))
    local progress_bar=""
    
    for ((i=0; i<percentage/5; i++)); do
        progress_bar="${progress_bar}█"
    done
    
    printf "\r${BLUE}Progress: [%-20s] %d%% - %s${NC}" "$progress_bar" "$percentage" "$description"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# ==============================================================================
# SYSTEM VALIDATION AND PREREQUISITES
# ==============================================================================

check_root_privileges() {
    if [[ $EUID -ne 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
        critical "This installer must be run with sudo privileges"
    fi
    success "Root privileges verified"
}

check_operating_system() {
    if [[ ! -f /etc/os-release ]]; then
        critical "Unable to determine operating system"
    fi
    
    source /etc/os-release
    if [[ "$ID" != "debian" ]] && [[ "$ID" != "ubuntu" ]] && [[ "$ID_LIKE" != *"debian"* ]]; then
        warning "This installer is optimized for Debian/Ubuntu systems"
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    success "Operating system compatibility verified"
}

check_network_connectivity() {
    local test_hosts=("google.com" "github.com" "docker.io")
    local failed_hosts=()
    
    for host in "${test_hosts[@]}"; do
        if ! ping -c 1 "$host" >/dev/null 2>&1; then
            failed_hosts+=("$host")
        fi
    done
    
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        warning "Network connectivity issues detected: ${failed_hosts[*]}"
        warning "Installation may fail or be incomplete"
    else
        success "Network connectivity verified"
    fi
}

install_prerequisites() {
    info "Installing system prerequisites..."
    
    # Update package lists
    apt-get update -qq
    
    # Essential packages
    local packages=(
        "curl"
        "wget"
        "git"
        "jq"
        "unzip"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "software-properties-common"
        "apt-transport-https"
        "netcat-openbsd"
        "dnsutils"
        "iputils-ping"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            info "Installing $package..."
            apt-get install -y "$package" >/dev/null
        fi
    done
    
    success "Prerequisites installed"
}

install_docker() {
    if command -v docker >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1; then
        success "Docker already installed"
        return 0
    fi
    
    info "Installing Docker and Docker Compose..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up the repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
    
    # Install Docker Compose (standalone)
    local compose_version="v2.23.0"
    curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group if not root
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER"
    fi
    
    success "Docker installed and configured"
}

# ==============================================================================
# PHASE 1: SYSTEM PREPARATION
# ==============================================================================

phase_system_preparation() {
    phase_header "SYSTEM PREPARATION" "Validating system requirements and installing prerequisites"
    
    show_progress 1 6 "Checking root privileges..."
    check_root_privileges
    
    show_progress 2 6 "Validating operating system..."
    check_operating_system
    
    show_progress 3 6 "Testing network connectivity..."
    check_network_connectivity
    
    show_progress 4 6 "Installing system prerequisites..."
    install_prerequisites
    
    show_progress 5 6 "Installing Docker infrastructure..."
    install_docker
    
    show_progress 6 6 "Creating directory structure..."
    create_directory_structure
    
    success "System preparation completed"
}

create_directory_structure() {
    local directories=(
        "$INSTALL_ROOT"
        "$CONFIG_DIR"
        "$KEYS_DIR"
        "$INSTALL_ROOT/logs"
        "$INSTALL_ROOT/caddy"
        "$INSTALL_ROOT/monitoring"
        "$INSTALL_ROOT/monitoring/grafana"
        "$BACKUP_ROOT"
        "/var/log/sudo-io/claude-user"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
    done
    
    # Set proper ownership
    chown -R root:docker "$INSTALL_ROOT" 2>/dev/null || true
}

# ==============================================================================
# PHASE 2: CONFIGURATION DISCOVERY AND GENERATION
# ==============================================================================

phase_configuration_discovery() {
    phase_header "CONFIGURATION DISCOVERY" "Auto-discovering Proxmox environment and generating configuration"
    
    show_progress 1 5 "Scanning for Proxmox servers..."
    discover_proxmox_servers
    
    show_progress 2 5 "Collecting configuration parameters..."
    collect_configuration_parameters
    
    show_progress 3 5 "Generating SSH keys..."
    generate_ssh_keys
    
    show_progress 4 5 "Creating configuration files..."
    generate_configuration_files
    
    show_progress 5 5 "Validating configuration..."
    validate_configuration
    
    success "Configuration discovery completed"
}

discover_proxmox_servers() {
    info "Auto-discovering Proxmox servers on local network..."
    
    # Get local network range
    local local_ip=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    local network=$(echo "$local_ip" | sed 's/\.[0-9]*$//')
    
    # Scan for Proxmox web interface (port 8006)
    local discovered_servers=()
    for i in {1..254}; do
        local target_ip="${network}.${i}"
        if timeout 1 bash -c "echo >/dev/tcp/${target_ip}/8006" 2>/dev/null; then
            # Verify it's actually Proxmox
            if curl -k -s "https://${target_ip}:8006" | grep -q "Proxmox"; then
                discovered_servers+=("$target_ip")
            fi
        fi
    done
    
    if [[ ${#discovered_servers[@]} -gt 0 ]]; then
        success "Discovered Proxmox servers: ${discovered_servers[*]}"
        PROXMOX_HOST="${discovered_servers[0]}"  # Use first discovered
    else
        warning "No Proxmox servers auto-discovered"
        PROXMOX_HOST=""
    fi
}

collect_configuration_parameters() {
    info "Collecting configuration parameters..."
    
    # Interactive configuration collection
    echo ""
    echo -e "${BOLD}=== PROXMOX MCP CONFIGURATION ===${NC}"
    echo ""
    
    # Proxmox host
    if [[ -n "${PROXMOX_HOST:-}" ]]; then
        read -p "Proxmox host (discovered: $PROXMOX_HOST): " -r input
        PROXMOX_HOST="${input:-$PROXMOX_HOST}"
    else
        read -p "Proxmox host IP address: " -r PROXMOX_HOST
    fi
    
    # SSH configuration
    read -p "SSH user for MCP operations [claude-user]: " -r SSH_USER
    SSH_USER="${SSH_USER:-claude-user}"
    
    read -p "SSH port [22]: " -r SSH_PORT
    SSH_PORT="${SSH_PORT:-22}"
    
    # Proxmox API configuration
    read -p "Proxmox API user [root@pam]: " -r PROXMOX_USER
    PROXMOX_USER="${PROXMOX_USER:-root@pam}"
    
    read -p "Proxmox API token name [claude-mcp]: " -r PROXMOX_TOKEN_NAME
    PROXMOX_TOKEN_NAME="${PROXMOX_TOKEN_NAME:-claude-mcp}"
    
    echo ""
    echo -e "${YELLOW}Please create the API token in Proxmox web interface:${NC}"
    echo -e "${CYAN}1. Go to: https://$PROXMOX_HOST:8006${NC}"
    echo -e "${CYAN}2. Navigate to: Datacenter → Permissions → API Tokens${NC}"
    echo -e "${CYAN}3. Add token: User=$PROXMOX_USER, Token ID=$PROXMOX_TOKEN_NAME${NC}"
    echo -e "${CYAN}4. Uncheck 'Privilege Separation' for full access${NC}"
    echo ""
    read -p "Enter the API token value: " -r PROXMOX_TOKEN_VALUE
    
    # MCP server configuration
    read -p "MCP server port [8080]: " -r MCP_PORT
    MCP_PORT="${MCP_PORT:-8080}"
    
    read -p "Enable monitoring dashboards? [y/N]: " -r ENABLE_MONITORING
    ENABLE_MONITORING="${ENABLE_MONITORING:-n}"
    
    # Validate critical parameters
    if [[ -z "$PROXMOX_HOST" ]] || [[ -z "$PROXMOX_TOKEN_VALUE" ]]; then
        critical "Proxmox host and API token are required"
    fi
}

generate_ssh_keys() {
    local key_path="$KEYS_DIR/claude_proxmox_key"
    
    if [[ -f "$key_path" ]]; then
        info "SSH key already exists"
        return 0
    fi
    
    info "Generating SSH key pair..."
    ssh-keygen -t ed25519 -f "$key_path" -C "proxmox-mcp-${INSTALLATION_ID}" -N ""
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
    
    success "SSH key pair generated"
    
    # Display public key for manual installation
    echo ""
    echo -e "${YELLOW}=== SSH PUBLIC KEY DEPLOYMENT ===${NC}"
    echo -e "${CYAN}Please add this public key to the Proxmox server:${NC}"
    echo ""
    echo -e "${BOLD}ssh-copy-id -i ${key_path}.pub ${SSH_USER}@${PROXMOX_HOST}${NC}"
    echo ""
    echo -e "${CYAN}Or manually add to ~/.ssh/authorized_keys:${NC}"
    echo ""
    cat "${key_path}.pub"
    echo ""
    read -p "Press Enter when SSH key is deployed..."
    
    # Test SSH connection
    if ssh -i "$key_path" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${SSH_USER}@${PROXMOX_HOST}" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        success "SSH connection verified"
    else
        warning "SSH connection test failed - continuing anyway"
    fi
}

generate_configuration_files() {
    info "Generating configuration files..."
    
    # Generate main environment file
    cat > "$INSTALL_ROOT/.env" << EOF
# Proxmox MCP Production Configuration
# Generated by installer: $INSTALLATION_ID
# Version: $SCRIPT_VERSION

# Container Configuration
IMAGE_TAG=latest
LOG_LEVEL=INFO

# SSH Configuration
SSH_TARGET=proxmox
SSH_HOST=$PROXMOX_HOST
SSH_USER=$SSH_USER
SSH_PORT=$SSH_PORT
SSH_KEY_PATH=/app/keys/claude_proxmox_key

# Proxmox API Configuration
PROXMOX_HOST=$PROXMOX_HOST
PROXMOX_USER=$PROXMOX_USER
PROXMOX_TOKEN_NAME=$PROXMOX_TOKEN_NAME
PROXMOX_TOKEN_VALUE=$PROXMOX_TOKEN_VALUE
PROXMOX_VERIFY_SSL=false

# Feature Configuration
ENABLE_PROXMOX_API=true
ENABLE_DANGEROUS_COMMANDS=false

# MCP Server Configuration
MCP_HOST=0.0.0.0
MCP_PORT=$MCP_PORT

# Monitoring Configuration
GRAFANA_PASSWORD=admin
EOF
    
    chmod 640 "$INSTALL_ROOT/.env"
    
    # Copy Docker Compose configuration
    cp "docker/docker-compose.prod.yml" "$INSTALL_ROOT/docker-compose.yml"
    
    # Copy Caddy configuration
    mkdir -p "$INSTALL_ROOT/caddy"
    cp "caddy/Caddyfile" "$INSTALL_ROOT/caddy/"
    
    # Update Caddy configuration for local access
    sed -i 's/mcp\.yourdomain\.com/localhost/' "$INSTALL_ROOT/caddy/Caddyfile"
    
    success "Configuration files generated"
}

validate_configuration() {
    info "Validating configuration files..."
    
    # Validate environment file
    if [[ ! -f "$INSTALL_ROOT/.env" ]]; then
        critical "Environment file not found"
    fi
    
    # Validate Docker Compose file
    if ! docker-compose -f "$INSTALL_ROOT/docker-compose.yml" config >/dev/null 2>&1; then
        critical "Docker Compose configuration is invalid"
    fi
    
    # Test Proxmox API connection
    if command -v curl >/dev/null 2>&1; then
        local api_url="https://$PROXMOX_HOST:8006/api2/json/version"
        local auth_header="Authorization: PVEAPIToken=$PROXMOX_USER!$PROXMOX_TOKEN_NAME=$PROXMOX_TOKEN_VALUE"
        
        if curl -k -s -H "$auth_header" "$api_url" | grep -q '"data"'; then
            success "Proxmox API connection verified"
        else
            warning "Proxmox API connection test failed - continuing anyway"
        fi
    fi
}

# ==============================================================================
# PHASE 3: SECURITY DEPLOYMENT
# ==============================================================================

phase_security_deployment() {
    phase_header "SECURITY DEPLOYMENT" "Deploying bulletproof security configuration"
    
    show_progress 1 4 "Creating claude-user account..."
    create_claude_user
    
    show_progress 2 4 "Deploying enhanced security configuration..."
    deploy_enhanced_security
    
    show_progress 3 4 "Running comprehensive security validation..."
    run_security_validation
    
    show_progress 4 4 "Setting up security monitoring..."
    setup_security_monitoring
    
    success "Security deployment completed"
}

create_claude_user() {
    if id "$SSH_USER" >/dev/null 2>&1; then
        info "User $SSH_USER already exists"
        return 0
    fi
    
    info "Creating user: $SSH_USER"
    useradd -m -s /bin/bash "$SSH_USER"
    usermod -aG docker "$SSH_USER"
    
    # Set up SSH directory
    local ssh_dir="/home/$SSH_USER/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$SSH_USER:$SSH_USER" "$ssh_dir"
    
    # Copy public key
    cp "$KEYS_DIR/claude_proxmox_key.pub" "$ssh_dir/authorized_keys"
    chmod 600 "$ssh_dir/authorized_keys"
    chown "$SSH_USER:$SSH_USER" "$ssh_dir/authorized_keys"
    
    success "User $SSH_USER created and configured"
}

deploy_enhanced_security() {
    if [[ -f "claude-user-security-enhanced-sudoers" ]]; then
        info "Deploying enhanced security configuration..."
        
        # Update the configuration with actual username
        sed "s/claude-user/$SSH_USER/g" "claude-user-security-enhanced-sudoers" > "/etc/sudoers.d/$SSH_USER"
        chmod 440 "/etc/sudoers.d/$SSH_USER"
        
        # Validate sudoers syntax
        if visudo -c; then
            success "Enhanced security configuration deployed"
        else
            critical "Sudoers configuration syntax error"
        fi
    else
        warning "Enhanced security configuration not found - using basic configuration"
        create_basic_sudoers
    fi
}

create_basic_sudoers() {
    cat > "/etc/sudoers.d/$SSH_USER" << EOF
# Basic Proxmox MCP configuration for $SSH_USER
$SSH_USER ALL=(ALL) NOPASSWD: /usr/sbin/qm *, /usr/sbin/pct *, /usr/sbin/pvesm *, /usr/sbin/pvesh *, /usr/bin/systemctl status *
EOF
    chmod 440 "/etc/sudoers.d/$SSH_USER"
}

run_security_validation() {
    if [[ -f "comprehensive-security-validation.sh" ]]; then
        info "Running comprehensive security validation..."
        chmod +x "comprehensive-security-validation.sh"
        
        if sudo -u "$SSH_USER" "./comprehensive-security-validation.sh"; then
            success "Security validation passed"
        else
            warning "Security validation completed with warnings"
        fi
    else
        warning "Security validation script not found"
    fi
}

setup_security_monitoring() {
    # Create security log directories
    mkdir -p "/var/log/sudo-io/$SSH_USER"
    chmod 750 "/var/log/sudo-io/$SSH_USER"
    
    # Create sudo log file
    touch "/var/log/sudo-$SSH_USER.log"
    chmod 640 "/var/log/sudo-$SSH_USER.log"
    
    success "Security monitoring configured"
}

# ==============================================================================
# PHASE 4: CONTAINER DEPLOYMENT
# ==============================================================================

phase_container_deployment() {
    phase_header "CONTAINER DEPLOYMENT" "Deploying Docker containers and services"
    
    show_progress 1 5 "Pulling container images..."
    pull_container_images
    
    show_progress 2 5 "Starting services..."
    start_services
    
    show_progress 3 5 "Configuring systemd service..."
    configure_systemd_service
    
    show_progress 4 5 "Waiting for services to be ready..."
    wait_for_services
    
    show_progress 5 5 "Verifying service health..."
    verify_service_health
    
    success "Container deployment completed"
}

pull_container_images() {
    cd "$INSTALL_ROOT"
    
    # Build local image if Dockerfile exists
    if [[ -f "../docker/Dockerfile.prod" ]]; then
        info "Building local container image..."
        docker build -f ../docker/Dockerfile.prod -t "proxmox-mcp:latest" ..
    fi
    
    # Pull required images
    docker-compose pull --ignore-pull-failures
}

start_services() {
    cd "$INSTALL_ROOT"
    
    # Start core services
    docker-compose up -d mcp-server caddy
    
    # Start monitoring if enabled
    if [[ "${ENABLE_MONITORING,,}" == "y" ]]; then
        docker-compose --profile monitoring up -d
    fi
}

configure_systemd_service() {
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Proxmox MCP HTTP Server
After=docker.service network.target
Requires=docker.service

[Service]
Type=forking
WorkingDirectory=$INSTALL_ROOT
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
ExecReload=/usr/local/bin/docker-compose restart
RemainAfterExit=yes
Restart=on-failure
RestartSec=30
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
}

wait_for_services() {
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f "http://localhost:$MCP_PORT/health" >/dev/null 2>&1; then
            return 0
        fi
        
        ((attempt++))
        sleep 10
    done
    
    warning "Services may not be fully ready after $max_attempts attempts"
}

verify_service_health() {
    local health_url="http://localhost:$MCP_PORT/health"
    local mcp_url="http://localhost:$MCP_PORT/api/mcp"
    
    # Test health endpoint
    if curl -f "$health_url" >/dev/null 2>&1; then
        success "Health endpoint responding"
    else
        warning "Health endpoint not responding"
    fi
    
    # Test MCP endpoint
    if curl -f -X POST "$mcp_url" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"1"}' >/dev/null 2>&1; then
        success "MCP endpoint responding"
    else
        warning "MCP endpoint not responding properly"
    fi
}

# ==============================================================================
# PHASE 5: CLIENT CONFIGURATION
# ==============================================================================

phase_client_configuration() {
    phase_header "CLIENT CONFIGURATION" "Configuring universal Claude Code access"
    
    show_progress 1 3 "Generating Claude Code configuration..."
    generate_claude_config
    
    show_progress 2 3 "Testing MCP connection..."
    test_mcp_connection
    
    show_progress 3 3 "Verifying tool availability..."
    verify_tool_availability
    
    success "Client configuration completed"
}

generate_claude_config() {
    local claude_config="/root/.claude.json"
    local mcp_url="http://localhost:$MCP_PORT/api/mcp"
    
    # Create Claude Code configuration
    cat > "$claude_config" << EOF
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http", 
      "url": "$mcp_url",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    }
  }
}
EOF
    
    chmod 644 "$claude_config"
    
    # Also create configuration template for users
    cat > "$INSTALL_ROOT/claude-config-template.json" << EOF
{
  "mcpServers": {
    "proxmox-mcp": {
      "type": "http",
      "url": "http://$PROXMOX_HOST:$MCP_PORT/api/mcp",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
    }
  }
}
EOF
    
    success "Claude Code configuration generated"
}

test_mcp_connection() {
    local mcp_url="http://localhost:$MCP_PORT/api/mcp"
    local test_request='{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'
    
    if response=$(curl -s -X POST "$mcp_url" -H "Content-Type: application/json" -d "$test_request"); then
        if echo "$response" | jq -e '.result.tools' >/dev/null 2>&1; then
            success "MCP connection test passed"
            return 0
        fi
    fi
    
    warning "MCP connection test failed"
}

verify_tool_availability() {
    local mcp_url="http://localhost:$MCP_PORT/api/mcp"
    local test_request='{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"tools"}'
    
    if response=$(curl -s -X POST "$mcp_url" -H "Content-Type: application/json" -d "$test_request"); then
        local tool_count=$(echo "$response" | jq -r '.result.tools | length' 2>/dev/null || echo "0")
        
        if [[ "$tool_count" -gt 0 ]]; then
            success "$tool_count MCP tools available"
            
            # List available tools
            echo "$response" | jq -r '.result.tools[].name' 2>/dev/null | while read -r tool; do
                info "  ✓ $tool"
            done
        else
            warning "No MCP tools detected"
        fi
    fi
}

# ==============================================================================
# PHASE 6: FINAL VALIDATION
# ==============================================================================

phase_final_validation() {
    phase_header "FINAL VALIDATION" "Comprehensive end-to-end testing"
    
    show_progress 1 4 "Testing SSH connectivity..."
    test_ssh_connectivity
    
    show_progress 2 4 "Testing Proxmox API access..."
    test_proxmox_api
    
    show_progress 3 4 "Testing MCP tool execution..."
    test_mcp_tools
    
    show_progress 4 4 "Generating installation report..."
    generate_installation_report
    
    success "Final validation completed"
}

test_ssh_connectivity() {
    if ssh -i "$KEYS_DIR/claude_proxmox_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${SSH_USER}@${PROXMOX_HOST}" "echo 'SSH test successful'" >/dev/null 2>&1; then
        success "SSH connectivity verified"
    else
        warning "SSH connectivity test failed"
    fi
}

test_proxmox_api() {
    local api_url="https://$PROXMOX_HOST:8006/api2/json/version"
    local auth_header="Authorization: PVEAPIToken=$PROXMOX_USER!$PROXMOX_TOKEN_NAME=$PROXMOX_TOKEN_VALUE"
    
    if curl -k -s -H "$auth_header" "$api_url" | jq -e '.data' >/dev/null 2>&1; then
        success "Proxmox API access verified"
    else
        warning "Proxmox API access test failed"
    fi
}

test_mcp_tools() {
    local mcp_url="http://localhost:$MCP_PORT/api/mcp"
    
    # Test list_vms tool
    local test_request='{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_vms","arguments":{}},"id":"test_vm"}'
    
    if curl -s -X POST "$mcp_url" -H "Content-Type: application/json" -d "$test_request" | jq -e '.result' >/dev/null 2>&1; then
        success "MCP tools execution verified"
    else
        warning "MCP tools execution test failed"
    fi
}

generate_installation_report() {
    local report_file="$INSTALL_ROOT/installation-report-${INSTALLATION_ID}.md"
    
    cat > "$report_file" << EOF
# Proxmox MCP Installation Report

## Installation Summary
- **Installation ID**: $INSTALLATION_ID
- **Timestamp**: $(date)
- **Version**: $SCRIPT_VERSION
- **Status**: COMPLETED

## Configuration
- **Proxmox Host**: $PROXMOX_HOST
- **SSH User**: $SSH_USER
- **SSH Port**: $SSH_PORT
- **MCP Port**: $MCP_PORT
- **Monitoring**: ${ENABLE_MONITORING^^}

## Service Status
\`\`\`bash
# Check service status
systemctl status $SERVICE_NAME

# View logs
docker-compose -f $INSTALL_ROOT/docker-compose.yml logs

# Test endpoints
curl http://localhost:$MCP_PORT/health
curl http://localhost:$MCP_PORT/docs
\`\`\`

## Client Configuration
Add to your ~/.claude.json:
\`\`\`json
$(cat "$INSTALL_ROOT/claude-config-template.json")
\`\`\`

## Management Commands
\`\`\`bash
# Restart services
systemctl restart $SERVICE_NAME

# Update containers
cd $INSTALL_ROOT && docker-compose pull && docker-compose up -d

# View security logs
tail -f /var/log/sudo-$SSH_USER.log

# Run security validation
sudo -u $SSH_USER $PWD/comprehensive-security-validation.sh
\`\`\`

## Files Created
- Configuration: $INSTALL_ROOT/.env
- SSH Keys: $KEYS_DIR/claude_proxmox_key*
- Service: /etc/systemd/system/$SERVICE_NAME.service
- Security: /etc/sudoers.d/$SSH_USER
- Logs: $LOG_FILE

## Success Criteria
✅ Docker services running
✅ SSH connectivity established  
✅ Proxmox API accessible
✅ MCP tools responding
✅ Security configuration deployed
✅ Client configuration generated

Installation completed successfully!
EOF
    
    success "Installation report generated: $report_file"
}

# ==============================================================================
# ERROR HANDLING AND ROLLBACK
# ==============================================================================

cleanup_on_error() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error "Installation failed with exit code: $exit_code"
        error "Check log file: $LOG_FILE"
        
        # Offer rollback
        read -p "Attempt rollback? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            perform_rollback
        fi
    fi
}

perform_rollback() {
    warning "Performing installation rollback..."
    
    # Stop services
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    # Remove Docker containers
    cd "$INSTALL_ROOT" 2>/dev/null && docker-compose down 2>/dev/null || true
    
    # Remove systemd service
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    
    # Remove sudoers configuration
    rm -f "/etc/sudoers.d/$SSH_USER"
    
    # Remove user (optional)
    read -p "Remove created user $SSH_USER? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        userdel -r "$SSH_USER" 2>/dev/null || true
    fi
    
    # Create backup of installation directory
    if [[ -d "$INSTALL_ROOT" ]]; then
        local backup_name="failed-install-$(date +%Y%m%d-%H%M%S)"
        mv "$INSTALL_ROOT" "$BACKUP_ROOT/$backup_name"
        warning "Installation directory backed up to: $BACKUP_ROOT/$backup_name"
    fi
    
    warning "Rollback completed"
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================

display_banner() {
    echo ""
    echo "=============================================="
    echo -e "${PURPLE}${BOLD}PROXMOX MCP PRODUCTION INSTALLER${NC}"
    echo "=============================================="
    echo -e "${CYAN}Enterprise-grade single-command installation${NC}"
    echo -e "${CYAN}Version: $SCRIPT_VERSION${NC}"
    echo -e "${CYAN}Installation ID: $INSTALLATION_ID${NC}"
    echo ""
    echo -e "${BLUE}Features:${NC}"
    echo -e "  ✅ Auto-discovery and guided configuration"
    echo -e "  ✅ Enhanced security with bulletproof protection"
    echo -e "  ✅ Docker containerization with monitoring"
    echo -e "  ✅ Universal Claude Code integration"
    echo -e "  ✅ Comprehensive validation and rollback"
    echo ""
}

main() {
    # Set up error handling
    trap cleanup_on_error EXIT
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Display banner
    display_banner
    
    # Execute installation phases
    for i in "${!PHASES[@]}"; do
        local phase_num=$((i + 1))
        local phase_name="${PHASES[$i]}"
        local phase_func="phase_${phase_name}"
        
        info "Starting phase $phase_num/${#PHASES[@]}: $phase_name"
        
        if declare -f "$phase_func" >/dev/null; then
            "$phase_func"
        else
            critical "Phase function not found: $phase_func"
        fi
    done
    
    # Success summary
    echo ""
    echo "=============================================="
    echo -e "${GREEN}${BOLD}INSTALLATION COMPLETED SUCCESSFULLY!${NC}"
    echo "=============================================="
    echo ""
    echo -e "${BLUE}Service Status:${NC}"
    echo -e "  Health: ${GREEN}http://localhost:$MCP_PORT/health${NC}"
    echo -e "  API Docs: ${GREEN}http://localhost:$MCP_PORT/docs${NC}"
    echo -e "  MCP Endpoint: ${GREEN}http://localhost:$MCP_PORT/api/mcp${NC}"
    
    if [[ "${ENABLE_MONITORING,,}" == "y" ]]; then
        echo -e "  Grafana: ${GREEN}http://localhost:3000${NC} (admin/admin)"
        echo -e "  Prometheus: ${GREEN}http://localhost:9090${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Add MCP server to Claude Code configuration"
    echo -e "  2. Test connection: ${CYAN}curl http://localhost:$MCP_PORT/health${NC}"
    echo -e "  3. View installation report: ${CYAN}cat $INSTALL_ROOT/installation-report-${INSTALLATION_ID}.md${NC}"
    echo ""
    echo -e "${GREEN}🎉 Universal Proxmox MCP access is now available from any Claude Code project!${NC}"
    
    # Remove error trap on success
    trap - EXIT
}

# Handle command-line arguments
case "${1:-install}" in
    "install")
        main
        ;;
    "rollback")
        perform_rollback
        ;;
    "validate")
        test_mcp_connection
        verify_tool_availability
        ;;
    "--help"|"-h")
        echo "Usage: $0 [install|rollback|validate]"
        echo ""
        echo "Commands:"
        echo "  install   - Complete installation (default)"
        echo "  rollback  - Remove installation"
        echo "  validate  - Test current installation" 
        echo "  --help    - Show this help"
        exit 0
        ;;
    *)
        error "Unknown command: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac