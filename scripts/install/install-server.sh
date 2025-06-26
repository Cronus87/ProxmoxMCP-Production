#!/bin/bash
# Quick install script for Proxmox MCP - Copy this to /opt/proxmox-mcp/install.sh

cat > /opt/proxmox-mcp/install.sh << 'EOF'
#!/bin/bash
# Proxmox MCP Master Installation Script
# Single-command installation automation for enterprise deployment

set -euo pipefail

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/installation.log"
readonly BACKUP_DIR="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Installation failed with exit code: $exit_code"
    echo -e "${RED}❌ INSTALLATION FAILED${NC}"
    echo "Check the log file for details: $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# Main installation process
main() {
    echo "=================================================================="
    echo -e "${BLUE}🚀 PROXMOX MCP INSTALLATION${NC}"
    echo "=================================================================="
    
    # Initialize log file
    log "Starting Proxmox MCP installation"
    
    # Phase 1: Prerequisites
    echo -e "${BLUE}Phase 1: System Prerequisites${NC}"
    
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
    
    # Phase 2: Check existing setup
    echo -e "${BLUE}Phase 2: Checking Current Setup${NC}"
    
    # Check if containers are running
    if docker ps | grep -q "proxmox-mcp"; then
        log_info "MCP containers found running"
        docker ps | grep "proxmox-mcp"
    else
        log_warning "No MCP containers currently running"
    fi
    
    # Check if docker-compose is configured
    if [[ -f "docker-compose.yml" ]]; then
        log_success "Docker compose configuration found"
        
        # Try to start services
        log_info "Starting MCP services..."
        if docker-compose up -d; then
            log_success "Services started successfully"
        else
            log_error "Failed to start services - check docker-compose.yml"
        fi
        
        # Wait a moment for startup
        sleep 10
        
        # Check status
        log_info "Service status:"
        docker-compose ps
        
    else
        log_error "docker-compose.yml not found"
        exit 1
    fi
    
    # Phase 3: Basic connectivity test
    echo -e "${BLUE}Phase 3: Testing Connectivity${NC}"
    
    # Test if MCP server is responding
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        log_success "MCP server responding on port 8080"
    else
        log_warning "MCP server not responding on port 8080"
    fi
    
    # Phase 4: Security check
    echo -e "${BLUE}Phase 4: Security Configuration${NC}"
    
    # Check claude-user exists
    if id "claude-user" >/dev/null 2>&1; then
        log_success "claude-user account exists"
        
        # Test basic sudo access
        if sudo -u claude-user sudo -l >/dev/null 2>&1; then
            log_success "claude-user has sudo access"
        else
            log_warning "claude-user sudo access issue"
        fi
    else
        log_warning "claude-user account not found"
    fi
    
    # Final summary
    echo
    echo "=================================================================="
    echo -e "${GREEN}🎉 PROXMOX MCP STATUS CHECK COMPLETE${NC}"
    echo "=================================================================="
    
    # Get server IP
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    
    echo "📊 SYSTEM STATUS:"
    echo "   Server IP: $server_ip"
    echo "   Docker: $(docker --version 2>/dev/null || echo 'Not available')"
    echo "   Proxmox: $(pveversion 2>/dev/null || echo 'Available')"
    echo
    echo "🔧 CURRENT SERVICES:"
    docker-compose ps 2>/dev/null || echo "   No docker-compose services found"
    echo
    echo "📱 POTENTIAL CLIENT CONFIGURATION:"
    echo "   Server URL: http://$server_ip:8080"
    echo "   Health URL: http://$server_ip:8080/health"
    echo
    echo "🔍 USEFUL COMMANDS:"
    echo "   View logs: docker-compose logs -f"
    echo "   Restart: docker-compose restart"
    echo "   Status: docker-compose ps"
    echo "   Stop: docker-compose down"
    echo
    log_success "Status check completed"
    echo "=================================================================="
}

# Script entry point
main "$@"
EOF

chmod +x /opt/proxmox-mcp/install.sh
echo "✅ Install script created at /opt/proxmox-mcp/install.sh"