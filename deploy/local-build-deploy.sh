#!/bin/bash
# Local Build and Deploy Script for Proxmox MCP Server
# This script builds the Docker image locally and deploys it to the Proxmox system

set -euo pipefail

# Configuration
DEPLOY_DIR="/opt/proxmox-mcp"
SERVICE_NAME="proxmox-mcp"
BACKUP_DIR="/opt/proxmox-mcp-backups"
MAX_BACKUPS=5
IMAGE_NAME="proxmox-mcp-server"
IMAGE_TAG="latest"

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
    log "Performing cleanup after error..."
    # Stop any partially started containers
    if [[ -d "$DEPLOY_DIR" ]]; then
        cd "$DEPLOY_DIR"
        docker-compose down --timeout 30 2>/dev/null || true
    fi
    
    # Remove any dangling images from failed build
    docker image prune -f --filter "dangling=true" 2>/dev/null || true
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

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running or user doesn't have permissions"
    fi
    
    log "✅ Docker is available and running"
}

# Create backup of current deployment
create_backup() {
    log "Creating backup of current deployment..."
    
    local backup_name="backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    if [[ -d "$DEPLOY_DIR" ]]; then
        # Stop services before backup if they're running
        cd "$DEPLOY_DIR"
        if docker-compose ps -q | grep -q .; then
            log "Stopping services for backup..."
            docker-compose down --timeout 30 || warn "Some services didn't stop gracefully"
        fi
        
        # Create backup
        cp -r "$DEPLOY_DIR" "$backup_path"
        log "Backup created at: $backup_path"
        
        # Cleanup old backups
        local backup_count=$(ls -1 "$BACKUP_DIR" | wc -l)
        if [[ $backup_count -gt $MAX_BACKUPS ]]; then
            log "Cleaning up old backups (keeping latest $MAX_BACKUPS)..."
            ls -1t "$BACKUP_DIR" | tail -n +$((MAX_BACKUPS + 1)) | xargs -I {} rm -rf "$BACKUP_DIR/{}"
        fi
    else
        warn "No existing deployment found to backup"
    fi
}

# Build Docker image locally
build_image() {
    log "Building Docker image locally..."
    
    if [[ ! -f "docker/Dockerfile.prod" ]]; then
        error "Dockerfile.prod not found. Run this script from the project root directory."
    fi
    
    if [[ ! -f "requirements-http.txt" ]]; then
        error "requirements-http.txt not found. Run this script from the project root directory."
    fi
    
    # Build with build args for metadata
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local version=$(cat VERSION 2>/dev/null || echo "dev")
    local vcs_ref=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    info "Build metadata:"
    info "  Date: $build_date"
    info "  Version: $version"
    info "  VCS Ref: $vcs_ref"
    
    docker build \
        -f docker/Dockerfile.prod \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg VERSION="$version" \
        --build-arg VCS_REF="$vcs_ref" \
        .
    
    log "✅ Docker image built successfully: $IMAGE_NAME:$IMAGE_TAG"
}

# Setup deployment directory
setup_deployment_dir() {
    log "Setting up deployment directory..."
    
    # Create deployment directory
    mkdir -p "$DEPLOY_DIR"
    
    # Create required subdirectories
    mkdir -p "$DEPLOY_DIR"/{logs,keys,config,caddy,monitoring/grafana,monitoring}
    
    # Copy configuration files from repository
    cp docker/docker-compose.prod.yml "$DEPLOY_DIR/docker-compose.yml"
    
    # Update docker-compose.yml to use local image (with validation)
    if [[ -f "$DEPLOY_DIR/docker-compose.yml" ]]; then
        # Create backup before modification
        cp "$DEPLOY_DIR/docker-compose.yml" "$DEPLOY_DIR/docker-compose.yml.bak"
        
        # Validate image name format
        if [[ "$IMAGE_NAME" =~ ^[a-zA-Z0-9._/-]+$ && "$IMAGE_TAG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            sed -i "s|ghcr.io/your-username/fullproxmoxmcp:\${IMAGE_TAG:-latest}|$IMAGE_NAME:$IMAGE_TAG|g" "$DEPLOY_DIR/docker-compose.yml"
            # Remove obsolete version directive
            sed -i '/^version:/d' "$DEPLOY_DIR/docker-compose.yml"
        else
            error "Invalid image name or tag format"
        fi
    else
        error "Docker compose file not found at expected location"
    fi
    
    # Copy and fix Caddyfile
    cat > "$DEPLOY_DIR/caddy/Caddyfile" << 'EOF'
# Caddyfile for Proxmox MCP Server
# Simplified configuration without unsupported directives

# Local development/production without domain
:80 {
    reverse_proxy mcp-server:8080
    
    # CORS headers for MCP clients
    header {
        Access-Control-Allow-Origin "*"
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With"
    }
    
    # Handle OPTIONS requests for CORS
    @options method OPTIONS
    respond @options 204
}

# Health check endpoint
:8081 {
    respond /health 200 {
        body "OK"
    }
}
EOF
    
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
SSH_HOST=localhost
SSH_USER=claude-user
SSH_PORT=22

# Proxmox API Configuration
PROXMOX_HOST=localhost
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
    chown -R root:root "$DEPLOY_DIR"
    chmod 640 "$DEPLOY_DIR/.env" 2>/dev/null || warn "Could not set .env file permissions"
}

# Deploy services
deploy_services() {
    log "Deploying services..."
    
    cd "$DEPLOY_DIR"
    
    # Start services
    docker-compose up -d --remove-orphans
    
    log "Services deployed"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Wait for services to be ready
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f -s http://localhost/docs > /dev/null 2>&1; then
            log "✅ Service is accessible via reverse proxy"
            break
        fi
        
        ((attempt++))
        info "Waiting for services to be ready... ($attempt/$max_attempts)"
        sleep 10
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        warn "⚠️  Service accessibility test failed after $max_attempts attempts"
    fi
    
    # Check container status
    cd "$DEPLOY_DIR"
    local running_containers=$(docker-compose ps -q | wc -l)
    local expected_containers=2  # mcp-server and caddy
    
    if [[ $running_containers -eq $expected_containers ]]; then
        log "✅ All expected containers are running"
    else
        warn "⚠️  Expected $expected_containers containers, found $running_containers"
    fi
    
    # Show container status
    info "Container status:"
    docker-compose ps
    
    log "Deployment verification completed"
}

# Rollback to previous version
rollback() {
    warn "Deployment failed - initiating rollback..."
    
    local latest_backup=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -1)
    if [[ -n "$latest_backup" && -d "$BACKUP_DIR/$latest_backup" ]]; then
        log "Rolling back to: $latest_backup"
        
        # Stop current services
        if [[ -d "$DEPLOY_DIR" ]]; then
            cd "$DEPLOY_DIR"
            docker-compose down --timeout 30 2>/dev/null || true
        fi
        
        # Restore backup safely
        if [[ -d "$DEPLOY_DIR" ]]; then
            mv "$DEPLOY_DIR" "${DEPLOY_DIR}.failed-$(date +%s)"
        fi
        cp -r "$BACKUP_DIR/$latest_backup" "$DEPLOY_DIR"
        
        # Start restored services
        cd "$DEPLOY_DIR"
        docker-compose up -d
        
        log "✅ Rollback completed"
    else
        error "❌ No backup found for rollback"
    fi
}

# Show deployment summary
show_summary() {
    log "🎉 Local build and deployment completed successfully!"
    
    echo ""
    echo "📋 Deployment Summary:"
    echo "======================"
    echo "   Service: $SERVICE_NAME"
    echo "   Directory: $DEPLOY_DIR"
    echo "   Image: $IMAGE_NAME:$IMAGE_TAG"
    echo "   Local IP: $(hostname -I | awk '{print $1}')"
    echo ""
    echo "🌐 Service Endpoints:"
    echo "   Web UI: http://$(hostname -I | awk '{print $1}')/docs"
    echo "   Health: http://$(hostname -I | awk '{print $1}')/health"
    echo "   Direct: http://$(hostname -I | awk '{print $1}'):8080"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Status: cd $DEPLOY_DIR && docker-compose ps"
    echo "   Logs: cd $DEPLOY_DIR && docker-compose logs -f"
    echo "   Restart: cd $DEPLOY_DIR && docker-compose restart"
    echo "   Stop: cd $DEPLOY_DIR && docker-compose down"
    echo ""
}

# Main deployment function
main() {
    log "🚀 Starting local build and deployment of Proxmox MCP Server"
    echo "=============================================================="
    
    # Set error trap for rollback
    trap rollback ERR
    
    check_permissions
    check_docker
    create_backup
    build_image
    setup_deployment_dir
    deploy_services
    verify_deployment
    show_summary
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "build")
        check_permissions
        check_docker
        build_image
        ;;
    "verify")
        verify_deployment
        ;;
    "backup")
        check_permissions
        create_backup
        ;;
    "rollback")
        check_permissions
        rollback
        ;;
    *)
        echo "Usage: $0 [deploy|build|verify|backup|rollback]"
        echo ""
        echo "Commands:"
        echo "  deploy   - Full build and deployment (default)"
        echo "  build    - Build Docker image only"
        echo "  verify   - Verify existing deployment"
        echo "  backup   - Create backup only"
        echo "  rollback - Rollback to previous backup"
        exit 1
        ;;
esac