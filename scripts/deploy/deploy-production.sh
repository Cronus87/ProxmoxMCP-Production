#!/bin/bash
# Production deployment script for Proxmox MCP Server
# Called by GitHub Actions CI/CD pipeline

set -euo pipefail

# Configuration
DEPLOY_DIR="/opt/proxmox-mcp"
SERVICE_NAME="proxmox-mcp"
BACKUP_DIR="/opt/proxmox-mcp-backups"
MAX_BACKUPS=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    cleanup_on_error
    exit 1
}

# Cleanup function for error handling
cleanup_on_error() {
    log "Cleaning up after error..."
    # Stop any running containers that might be in inconsistent state
    if [[ -d "$DEPLOY_DIR" ]]; then
        cd "$DEPLOY_DIR"
        docker-compose down --timeout 30 2>/dev/null || true
    fi
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Ensure we're running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
    fi
}

# Create backup of current deployment
create_backup() {
    log "Creating backup of current deployment..."
    
    local backup_name="backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    if [[ -d "$DEPLOY_DIR" ]]; then
        # Stop services before backup
        systemctl stop "$SERVICE_NAME" || warn "Service was not running"
        
        # Create backup
        cp -r "$DEPLOY_DIR" "$backup_path"
        log "Backup created at: $backup_path"
        
        # Cleanup old backups safely
        local backup_count=$(ls -1 "$BACKUP_DIR" | wc -l)
        if [[ $backup_count -gt $MAX_BACKUPS ]]; then
            log "Cleaning up old backups (keeping latest $MAX_BACKUPS)..."
            cd "$BACKUP_DIR"
            ls -1t | tail -n +$((MAX_BACKUPS + 1)) | while read -r backup_to_remove; do
                if [[ -d "$backup_to_remove" && "$backup_to_remove" =~ ^backup-[0-9]{8}_[0-9]{6}$ ]]; then
                    rm -rf "$backup_to_remove"
                    log "Removed old backup: $backup_to_remove"
                fi
            done
        fi
    else
        warn "No existing deployment found to backup"
    fi
}

# Setup deployment directory
setup_deployment_dir() {
    log "Setting up deployment directory..."
    
    # Create deployment directory
    mkdir -p "$DEPLOY_DIR"
    
    # Create required subdirectories
    mkdir -p "$DEPLOY_DIR"/{logs,keys,config,monitoring/grafana,monitoring}
    
    # Copy configuration files from repository
    cp docker/docker-compose.prod.yml "$DEPLOY_DIR/docker-compose.yml"
    cp caddy/Caddyfile "$DEPLOY_DIR/caddy/"
    
    # Create environment file if it doesn't exist
    if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
        log "Creating default environment file..."
        cat > "$DEPLOY_DIR/.env" << 'EOF'
# Proxmox MCP Server Environment Configuration
# Update these values for your environment

# Container image
IMAGE_TAG=latest

# Logging
LOG_LEVEL=INFO

# SSH Configuration
SSH_TARGET=proxmox
SSH_HOST=192.168.1.137
SSH_USER=claude-user
SSH_PORT=22

# Proxmox API Configuration
PROXMOX_HOST=192.168.1.137
PROXMOX_USER=root@pam
PROXMOX_TOKEN_NAME=claude-mcp
PROXMOX_TOKEN_VALUE=your-token-here
PROXMOX_VERIFY_SSL=false

# Feature Flags
ENABLE_PROXMOX_API=true
ENABLE_DANGEROUS_COMMANDS=false

# Monitoring (optional)
GRAFANA_PASSWORD=admin
EOF
        warn "Environment file created at $DEPLOY_DIR/.env - Please update with your values"
    fi
    
    # Set proper permissions
    chown -R root:docker "$DEPLOY_DIR"
    chmod 640 "$DEPLOY_DIR/.env"
}

# Update container image
update_container() {
    log "Updating container image..."
    
    local image_tag="${IMAGE_TAG:-latest}"
    info "Using image tag: $image_tag"
    
    cd "$DEPLOY_DIR"
    
    # Update environment with new image tag (with validation)
    if [[ "$image_tag" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        if grep -q "IMAGE_TAG=" .env; then
            sed -i "s/IMAGE_TAG=.*/IMAGE_TAG=$image_tag/" .env
        else
            echo "IMAGE_TAG=$image_tag" >> .env
        fi
    else
        error "Invalid image tag format: $image_tag"
    fi
    
    # Pull new image
    docker-compose pull
    
    log "Container image updated"
}

# Deploy services
deploy_services() {
    log "Deploying services..."
    
    cd "$DEPLOY_DIR"
    
    # Start services with new image
    docker-compose up -d
    
    log "Services deployed"
}

# Setup systemd service
setup_systemd_service() {
    log "Setting up systemd service..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Proxmox MCP HTTP Server
After=docker.service network.target
Requires=docker.service

[Service]
Type=forking
WorkingDirectory=$DEPLOY_DIR
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
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    log "Systemd service configured and started"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Wait for services to be ready
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f http://localhost/health > /dev/null 2>&1; then
            log "✅ Health check passed"
            break
        fi
        
        ((attempt++))
        info "Waiting for services to be ready... ($attempt/$max_attempts)"
        sleep 10
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error "❌ Health check failed after $max_attempts attempts"
    fi
    
    # Test MCP endpoint
    if curl -f http://localhost/api/mcp > /dev/null 2>&1; then
        log "✅ MCP endpoint accessible"
    else
        warn "⚠️  MCP endpoint test failed"
    fi
    
    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "✅ Systemd service is active"
    else
        warn "⚠️  Systemd service is not active"
    fi
    
    log "Deployment verification completed"
}

# Rollback to previous version
rollback() {
    error "Deployment failed - implement rollback logic here"
    # TODO: Implement rollback to previous backup
}

# Main deployment function
main() {
    log "🚀 Starting production deployment of Proxmox MCP Server"
    echo "=============================================================="
    
    # Set error trap for rollback
    trap rollback ERR
    
    check_permissions
    create_backup
    setup_deployment_dir
    update_container
    deploy_services
    setup_systemd_service
    verify_deployment
    
    log "🎉 Production deployment completed successfully!"
    
    echo ""
    echo "📋 Deployment Summary:"
    echo "======================"
    echo "   Service: $SERVICE_NAME"
    echo "   Directory: $DEPLOY_DIR"
    echo "   Image: $(grep IMAGE_TAG $DEPLOY_DIR/.env || echo 'latest')"
    echo "   Health: http://$(hostname -I | awk '{print $1}')/health"
    echo "   MCP API: http://$(hostname -I | awk '{print $1}')/api/mcp"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Status: systemctl status $SERVICE_NAME"
    echo "   Logs: cd $DEPLOY_DIR && docker-compose logs -f"
    echo "   Restart: systemctl restart $SERVICE_NAME"
    echo ""
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "verify")
        verify_deployment
        ;;
    "backup")
        create_backup
        ;;
    *)
        echo "Usage: $0 [deploy|verify|backup]"
        echo ""
        echo "Commands:"
        echo "  deploy  - Full production deployment (default)"
        echo "  verify  - Verify existing deployment"
        echo "  backup  - Create backup only"
        exit 1
        ;;
esac