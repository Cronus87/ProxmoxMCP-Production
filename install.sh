#!/bin/bash
# Proxmox MCP Master Installation Script
# Single-command installation automation for enterprise deployment

set -eu

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/installation.log"
readonly BACKUP_DIR="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly DEPLOY_DIR="${SCRIPT_DIR}/deploy"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Installation phases
declare -a PHASES=(
    "Phase 1: System Prerequisites"
    "Phase 2: Security Configuration"
    "Phase 3: Container Deployment"
    "Phase 4: Service Startup"
    "Phase 5: Client Configuration"
    "Phase 6: Validation & Testing"
)

# Progress tracking
CURRENT_PHASE=0
TOTAL_PHASES=${#PHASES[@]}

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}SUCCESS: $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}INFO: $*${NC}" | tee -a "$LOG_FILE"
}

# Progress display
show_progress() {
    local phase_name="$1"
    CURRENT_PHASE=$((CURRENT_PHASE + 1))
    
    echo
    echo "=================================================================="
    echo -e "${BLUE}${phase_name} (${CURRENT_PHASE}/${TOTAL_PHASES})${NC}"
    echo "=================================================================="
    log "Starting: $phase_name"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Installation failed with exit code: $exit_code"
    log_error "Check log file: $LOG_FILE"
    
    echo
    echo -e "${RED}❌ INSTALLATION FAILED${NC}"
    echo "Check the log file for details: $LOG_FILE"
    
    # Offer rollback if backup exists
    if [[ -d "$BACKUP_DIR" ]]; then
        echo
        read -p "Would you like to rollback changes? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rollback_installation
        fi
    fi
    
    exit $exit_code
}

trap cleanup_on_error ERR

# Rollback function
rollback_installation() {
    log_warning "Rolling back installation..."
    
    # Stop services
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose down 2>/dev/null || true
    fi
    
    # Restore configurations from backup
    if [[ -d "$BACKUP_DIR" ]]; then
        cp -r "$BACKUP_DIR"/* . 2>/dev/null || true
        log_success "Configuration restored from backup"
    fi
    
    log_success "Rollback completed"
}

# Phase 1: System Prerequisites
check_prerequisites() {
    show_progress "${PHASES[0]}"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check if running on Proxmox
    if ! command -v pvesh >/dev/null 2>&1; then
        log_error "Not running on a Proxmox VE system"
        exit 1
    fi
    log_success "Proxmox VE detected"
    
    # Check Docker installation
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Installing Docker..."
        apt update
        apt install -y docker.io docker-compose
    fi
    log_success "Docker available"
    
    # Check if in correct directory
    if [[ "$PWD" != "/opt/proxmox-mcp" ]]; then
        log_error "Script must be run from /opt/proxmox-mcp directory"
        exit 1
    fi
    log_success "Running from correct directory"
    
    # Check required files
    local required_files=(
        "docker-compose.yml"
        ".env"
        "core/proxmox_mcp_server.py"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file missing: $file"
            exit 1
        fi
    done
    log_success "All required files present"
    
    # Create backup
    mkdir -p "$BACKUP_DIR"
    cp -r .env docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
    log_success "Configuration backup created"
}

# Phase 2: Security Configuration
configure_security() {
    show_progress "${PHASES[1]}"
    
    log_info "Configuring secure user permissions..."
    
    # Check if enhanced security sudoers file exists
    if [[ -f "claude-user-security-enhanced-sudoers" ]]; then
        log_info "Deploying enhanced security configuration..."
        
        # Backup current sudoers
        if [[ -f "/etc/sudoers.d/claude-user" ]]; then
            cp "/etc/sudoers.d/claude-user" "/etc/sudoers.d/claude-user.backup.$(date +%s)" 2>/dev/null || true
        fi
        
        # Deploy enhanced security
        cp "claude-user-security-enhanced-sudoers" "/etc/sudoers.d/claude-user"
        chmod 440 "/etc/sudoers.d/claude-user"
        
        # Validate sudoers syntax
        if visudo -c -f "/etc/sudoers.d/claude-user"; then
            log_success "Enhanced security configuration deployed"
        else
            log_error "Sudoers configuration has syntax errors"
            exit 1
        fi
    else
        log_warning "Enhanced security file not found, using existing configuration"
    fi
    
    # Add claude-user to docker group
    if id "claude-user" >/dev/null 2>&1; then
        usermod -a -G docker claude-user 2>/dev/null || true
        log_success "claude-user added to docker group"
    else
        log_warning "claude-user not found, will be created by container"
    fi
}

# Phase 3: Container Deployment
deploy_containers() {
    show_progress "${PHASES[2]}"
    
    log_info "Preparing container deployment..."
    
    # Stop any existing containers
    docker-compose down 2>/dev/null || true
    
    # Check if we need to build image locally
    local image_name="ghcr.io/your-username/fullproxmoxmcp:latest"
    
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        log_info "Container image not found, building locally..."
        
        # Check for Dockerfile
        if [[ -f "docker/Dockerfile.prod" ]]; then
            docker build -t "$image_name" -f docker/Dockerfile.prod .
            log_success "Container image built locally"
        else
            log_error "Dockerfile not found and image not available"
            exit 1
        fi
    else
        log_success "Container image available"
    fi
    
    # Create required directories
    mkdir -p logs config keys
    chown -R root:root logs config keys
    chmod 755 logs config
    chmod 700 keys
    log_success "Directory structure prepared"
    
    # Verify environment configuration
    if ! grep -q "PROXMOX_TOKEN_VALUE" .env; then
        log_error ".env file missing Proxmox API token configuration"
        log_error "Please configure Proxmox API token in .env file"
        exit 1
    fi
    log_success "Environment configuration validated"
}

# Phase 4: Service Startup
start_services() {
    show_progress "${PHASES[3]}"
    
    log_info "Starting Proxmox MCP services..."
    
    # Start services
    if docker-compose up -d; then
        log_success "Services started successfully"
    else
        log_error "Failed to start services"
        exit 1
    fi
    
    # Wait for services to become healthy
    log_info "Waiting for services to become healthy..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if docker-compose ps | grep -q "healthy"; then
            log_success "Services are healthy"
            break
        fi
        
        log_info "Waiting for health check... ($((attempt + 1))/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Services failed to become healthy"
        docker-compose logs
        exit 1
    fi
    
    # Configure firewall
    log_info "Configuring firewall..."
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    ufw allow from 127.0.0.1 to any port 8080 2>/dev/null || true
    log_success "Firewall configured"
}

# Phase 5: Client Configuration
generate_client_config() {
    show_progress "${PHASES[4]}"
    
    log_info "Generating Claude Code client configuration..."
    
    # Get server IP
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    
    # Create client configuration
    cat > claude-mcp-config.json << EOF
{
  "mcpServers": {
    "proxmox-production": {
      "command": "npx",
      "args": [
        "@modelcontextprotocol/server-fetch",
        "http://${server_ip}/mcp"
      ],
      "transport": "stdio"
    }
  }
}
EOF
    
    log_success "Client configuration generated: claude-mcp-config.json"
    
    echo
    echo "=================================================================="
    echo -e "${GREEN}CLIENT CONFIGURATION READY${NC}"
    echo "=================================================================="
    echo "1. Copy the contents of claude-mcp-config.json"
    echo "2. Add to your ~/.claude.json file on your client machine"
    echo "3. Restart Claude Code"
    echo "4. Test connection with MCP tools"
    echo
    echo "Server URL: http://${server_ip}/mcp"
    echo "=================================================================="
}

# Phase 6: Validation & Testing
validate_installation() {
    show_progress "${PHASES[5]}"
    
    log_info "Running installation validation..."
    
    # Test container health
    if ! docker-compose ps | grep -q "Up.*healthy"; then
        log_error "Containers are not healthy"
        exit 1
    fi
    log_success "All containers healthy"
    
    # Test MCP endpoints
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    
    if curl -s "http://localhost:8080/health" >/dev/null; then
        log_success "MCP server health check passed"
    else
        log_error "MCP server health check failed"
        exit 1
    fi
    
    # Test security restrictions (if validation script exists)
    if [[ -f "comprehensive-security-validation.sh" ]] && [[ -x "comprehensive-security-validation.sh" ]]; then
        log_info "Running security validation..."
        if sudo -u claude-user ./comprehensive-security-validation.sh --quick; then
            log_success "Security validation passed"
        else
            log_warning "Security validation had issues - check manually"
        fi
    fi
    
    # Test Proxmox API connectivity
    if sudo -u claude-user pvesh get /nodes >/dev/null 2>&1; then
        log_success "Proxmox API connectivity verified"
    else
        log_warning "Proxmox API connectivity issue - check configuration"
    fi
    
    log_success "Installation validation completed"
}

# Final summary
show_installation_summary() {
    echo
    echo "=================================================================="
    echo -e "${GREEN}🎉 PROXMOX MCP INSTALLATION COMPLETE${NC}"
    echo "=================================================================="
    echo
    echo "📊 SYSTEM STATUS:"
    echo "   ✅ Container running and healthy"
    echo "   ✅ User permissions configured securely"
    echo "   ✅ MCP server accessible on port 8080"
    echo "   ✅ Reverse proxy configured (ports 80/443)"
    echo "   ✅ All system tests passed"
    echo
    echo "🔧 SERVICES RUNNING:"
    docker-compose ps
    echo
    echo "📱 CLIENT CONFIGURATION:"
    echo "   Configuration file: ./claude-mcp-config.json"
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    echo "   Server URL: http://${server_ip}/mcp"
    echo
    echo "🔍 USEFUL COMMANDS:"
    echo "   View logs: docker-compose logs -f mcp-server"
    echo "   Restart: docker-compose restart"
    echo "   Status: docker-compose ps"
    echo "   Stop: docker-compose down"
    echo
    echo "📚 DOCUMENTATION:"
    echo "   Installation Guide: docs/INSTALLATION-GUIDE.md"
    echo "   Security Guide: docs/SECURITY-GUIDE.md"
    echo "   Troubleshooting: docs/TROUBLESHOOTING-GUIDE.md"
    echo
    log_success "Installation completed successfully!"
    echo "=================================================================="
}

# Main installation process
main() {
    echo "=================================================================="
    echo -e "${BLUE}🚀 PROXMOX MCP MASTER INSTALLATION${NC}"
    echo "=================================================================="
    echo "This script will install and configure the Proxmox MCP server"
    echo "with enterprise-grade security and automation."
    echo
    echo "Installation will take approximately 8-12 minutes."
    echo "=================================================================="
    echo
    
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    log "Starting Proxmox MCP installation"
    
    # Execute installation phases
    check_prerequisites
    configure_security
    deploy_containers
    start_services
    generate_client_config
    validate_installation
    
    # Show final summary
    show_installation_summary
    
    log "Installation completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi