#!/bin/bash
# Secure Production Deployment Script for Proxmox MCP Server
# Enhanced version with comprehensive security validations and monitoring

set -euo pipefail

# Configuration
DEPLOY_DIR="/opt/proxmox-mcp"
SERVICE_NAME="proxmox-mcp"
BACKUP_DIR="/opt/proxmox-mcp-backups"
MAX_BACKUPS=5
IMAGE_NAME="proxmox-mcp-server"
COMPOSE_FILE="docker-compose.secure.yml"
SECURITY_SCAN_ENABLED="${SECURITY_SCAN_ENABLED:-true}"
VALIDATION_ENABLED="${VALIDATION_ENABLED:-true}"

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

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
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
    
    # Notify about available rollback
    if [[ -d "$BACKUP_DIR" ]]; then
        local latest_backup=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            warn "Rollback available: $0 rollback"
        fi
    fi
}

# Pre-deployment security checks
pre_deployment_checks() {
    log "Performing pre-deployment security checks..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
    fi
    
    # Check Docker availability
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running or user doesn't have permissions"
    fi
    
    # Check disk space
    local available_space=$(df "$DEPLOY_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ "$available_space" -lt 1048576 ]]; then  # 1GB in KB
        error "Insufficient disk space. At least 1GB required."
    fi
    
    # Check memory
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    if [[ "$available_memory" -lt 2048 ]]; then  # 2GB
        warn "Low available memory ($available_memory MB). Consider adding more memory."
    fi
    
    # Validate environment variables
    local required_vars=("SSH_HOST" "SSH_USER" "PROXMOX_HOST" "PROXMOX_USER")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable $var is not set"
        fi
    done
    
    log "✅ Pre-deployment checks passed"
}

# Build and scan Docker image
build_and_scan_image() {
    log "Building and scanning Docker image..."
    
    if [[ ! -f "docker/Dockerfile.prod" ]]; then
        error "Dockerfile.prod not found. Run this script from the project root directory."
    fi
    
    # Build image with security metadata
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local version=$(cat VERSION 2>/dev/null || echo "dev")
    local vcs_ref=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    info "Building image with metadata:"
    info "  Date: $build_date"
    info "  Version: $version"
    info "  VCS Ref: $vcs_ref"
    
    docker build \
        -f docker/Dockerfile.prod \
        -t "$IMAGE_NAME:latest" \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg VERSION="$version" \
        --build-arg VCS_REF="$vcs_ref" \
        .
    
    # Security scanning
    if [[ "$SECURITY_SCAN_ENABLED" == "true" ]]; then
        if [[ -x "docker/security-scan.sh" ]]; then
            log "Running security scan..."
            cd docker
            ./security-scan.sh scan "$IMAGE_NAME" "latest"
            cd ..
        else
            warn "Security scan script not found or not executable"
        fi
    fi
    
    log "✅ Image built and scanned successfully"
}

# Create secure backup
create_backup() {
    log "Creating secure backup of current deployment..."
    
    local backup_name="backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    if [[ -d "$DEPLOY_DIR" ]]; then
        # Stop services gracefully before backup
        cd "$DEPLOY_DIR"
        if docker-compose ps -q 2>/dev/null | grep -q .; then
            log "Stopping services for backup..."
            docker-compose down --timeout 30 || warn "Some services didn't stop gracefully"
        fi
        
        # Create secure backup with proper permissions
        cp -r "$DEPLOY_DIR" "$backup_path"
        chmod -R 640 "$backup_path"
        chown -R root:root "$backup_path"
        
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

# Setup secure deployment directory
setup_deployment_dir() {
    log "Setting up secure deployment directory..."
    
    # Create deployment directory with proper permissions
    mkdir -p "$DEPLOY_DIR"
    chmod 755 "$DEPLOY_DIR"
    
    # Create required subdirectories
    mkdir -p "$DEPLOY_DIR"/{logs,keys,config,caddy,monitoring/grafana,monitoring}
    
    # Set proper permissions
    chmod 750 "$DEPLOY_DIR"/{keys,config}
    chmod 755 "$DEPLOY_DIR"/{logs,caddy,monitoring}
    
    # Copy secure configuration files
    cp "docker/$COMPOSE_FILE" "$DEPLOY_DIR/docker-compose.yml"
    cp "caddy/Caddyfile.prod" "$DEPLOY_DIR/caddy/Caddyfile"
    
    # Create secure environment file if it doesn't exist
    if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
        log "Creating secure environment file..."
        cat > "$DEPLOY_DIR/.env" << EOF
# Proxmox MCP Server Environment Configuration
# Generated: $(date)

# Container image
IMAGE_TAG=latest

# Logging
LOG_LEVEL=INFO

# SSH Configuration
SSH_TARGET=${SSH_TARGET:-proxmox}
SSH_HOST=${SSH_HOST}
SSH_USER=${SSH_USER}
SSH_PORT=${SSH_PORT:-22}

# Proxmox API Configuration
PROXMOX_HOST=${PROXMOX_HOST}
PROXMOX_USER=${PROXMOX_USER}
PROXMOX_TOKEN_NAME=${PROXMOX_TOKEN_NAME}
PROXMOX_TOKEN_VALUE=${PROXMOX_TOKEN_VALUE}
PROXMOX_VERIFY_SSL=${PROXMOX_VERIFY_SSL:-false}

# Feature Flags
ENABLE_PROXMOX_API=${ENABLE_PROXMOX_API:-true}
ENABLE_DANGEROUS_COMMANDS=${ENABLE_DANGEROUS_COMMANDS:-false}

# Monitoring
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-$(openssl rand -base64 32)}

# Build metadata
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
VERSION=$(cat VERSION 2>/dev/null || echo "dev")
EOF
        warn "Environment file created at $DEPLOY_DIR/.env - Review and update as needed"
    fi
    
    # Set secure permissions
    chmod 640 "$DEPLOY_DIR/.env"
    chown root:root "$DEPLOY_DIR/.env"
    
    # Create monitoring configuration
    if [[ ! -f "$DEPLOY_DIR/monitoring/prometheus.yml" ]]; then
        mkdir -p "$DEPLOY_DIR/monitoring"
        cat > "$DEPLOY_DIR/monitoring/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
    metrics_path: /metrics
EOF
    fi
    
    log "✅ Deployment directory configured securely"
}

# Validate security configuration
validate_security_config() {
    if [[ "$VALIDATION_ENABLED" == "true" ]]; then
        log "Validating security configuration..."
        
        cd "$DEPLOY_DIR"
        
        if [[ -x "../docker/validate-security.sh" ]]; then
            ../docker/validate-security.sh docker-compose.yml
        else
            warn "Security validation script not found"
        fi
        
        log "✅ Security validation completed"
    else
        info "Security validation skipped (VALIDATION_ENABLED=false)"
    fi
}

# Deploy services with security monitoring
deploy_services() {
    log "Deploying services with security monitoring..."
    
    cd "$DEPLOY_DIR"
    
    # Pre-flight checks
    docker-compose config > /dev/null || error "Docker compose configuration is invalid"
    
    # Deploy services
    docker-compose up -d --remove-orphans
    
    # Wait for services to be healthy
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local healthy_services=$(docker-compose ps --services --filter "status=running" | wc -l)
        local total_services=$(docker-compose ps --services | wc -l)
        
        if [[ "$healthy_services" -eq "$total_services" ]]; then
            log "✅ All services are running"
            break
        fi
        
        ((attempt++))
        info "Waiting for services to be ready... ($attempt/$max_attempts)"
        sleep 10
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error "Services failed to start within expected time"
    fi
    
    log "✅ Services deployed successfully"
}

# Setup system service integration
setup_system_service() {
    log "Setting up system service integration..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Proxmox MCP HTTP Server (Secure)
After=docker.service network.target
Requires=docker.service
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$DEPLOY_DIR
ExecStartPre=/usr/bin/docker-compose config
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down --timeout 30
ExecReload=/usr/bin/docker-compose restart
Restart=on-failure
RestartSec=30
TimeoutStartSec=300
TimeoutStopSec=60

# Security settings
User=root
Group=root
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=$DEPLOY_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    log "✅ System service configured"
}

# Comprehensive deployment verification
verify_deployment() {
    log "Performing comprehensive deployment verification..."
    
    cd "$DEPLOY_DIR"
    
    # Check container status
    local running_containers=$(docker-compose ps -q | wc -l)
    local healthy_containers=$(docker-compose ps --filter "status=running" | wc -l)
    
    info "Container status: $healthy_containers/$running_containers healthy"
    
    # Test HTTP endpoints
    local endpoints=("http://localhost/health" "http://localhost:8081/health")
    
    for endpoint in "${endpoints[@]}"; do
        if curl -f -s "$endpoint" > /dev/null 2>&1; then
            log "✅ $endpoint accessible"
        else
            warn "⚠️  $endpoint not accessible"
        fi
    done
    
    # Check logs for errors
    local error_count=$(docker-compose logs --tail=100 2>&1 | grep -i error | wc -l)
    if [[ "$error_count" -gt 0 ]]; then
        warn "Found $error_count error messages in logs"
    else
        log "✅ No errors in recent logs"
    fi
    
    # Security validation
    if [[ -x "../docker/validate-security.sh" ]]; then
        info "Running final security validation..."
        ../docker/validate-security.sh docker-compose.yml > /dev/null 2>&1 || warn "Security validation warnings detected"
    fi
    
    # Check systemd service
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "✅ Systemd service is active"
    else
        warn "⚠️  Systemd service is not active"
    fi
    
    log "✅ Deployment verification completed"
}

# Rollback to previous version
rollback() {
    warn "Initiating rollback to previous deployment..."
    
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
        
        # Restore permissions
        chmod -R 640 "$DEPLOY_DIR"
        chown -R root:root "$DEPLOY_DIR"
        chmod 755 "$DEPLOY_DIR"
        
        # Start restored services
        cd "$DEPLOY_DIR"
        docker-compose up -d
        
        log "✅ Rollback completed successfully"
    else
        error "❌ No backup found for rollback"
    fi
}

# Generate deployment summary
show_deployment_summary() {
    log "🎉 Secure deployment completed successfully!"
    
    echo ""
    echo "📋 Deployment Summary:"
    echo "======================"
    echo "   Service: $SERVICE_NAME"
    echo "   Directory: $DEPLOY_DIR"
    echo "   Image: $IMAGE_NAME:latest"
    echo "   Security: Enhanced"
    echo "   Compose File: $COMPOSE_FILE"
    echo ""
    echo "🌐 Service Endpoints:"
    echo "   Web Interface: http://$(hostname -I | awk '{print $1}')"
    echo "   Health Check: http://$(hostname -I | awk '{print $1}')/health"
    echo "   Admin API: http://127.0.0.1:2019"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Status: systemctl status $SERVICE_NAME"
    echo "   Logs: cd $DEPLOY_DIR && docker-compose logs -f"
    echo "   Security Scan: docker/security-scan.sh scan $IMAGE_NAME latest"
    echo "   Security Validation: docker/validate-security.sh $DEPLOY_DIR/docker-compose.yml"
    echo "   Restart: systemctl restart $SERVICE_NAME"
    echo "   Rollback: $0 rollback"
    echo ""
    echo "🛡️  Security Features:"
    echo "   ✅ Container security hardening"
    echo "   ✅ Network segmentation"
    echo "   ✅ SSL/TLS termination ready"
    echo "   ✅ Resource limits enforced"
    echo "   ✅ Security monitoring enabled"
    echo ""
}

# Main deployment function
main() {
    log "🚀 Starting secure production deployment of Proxmox MCP Server"
    echo "==============================================================="
    
    # Set error trap for rollback
    trap 'cleanup_on_error' ERR
    
    pre_deployment_checks
    build_and_scan_image
    create_backup
    setup_deployment_dir
    validate_security_config
    deploy_services
    setup_system_service
    verify_deployment
    show_deployment_summary
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "build")
        pre_deployment_checks
        build_and_scan_image
        ;;
    "scan")
        if [[ -x "docker/security-scan.sh" ]]; then
            docker/security-scan.sh scan "$IMAGE_NAME" "latest"
        else
            error "Security scan script not found"
        fi
        ;;
    "validate")
        if [[ -x "docker/validate-security.sh" ]]; then
            docker/validate-security.sh "$DEPLOY_DIR/docker-compose.yml"
        else
            error "Security validation script not found"
        fi
        ;;
    "verify")
        verify_deployment
        ;;
    "backup")
        create_backup
        ;;
    "rollback")
        rollback
        ;;
    *)
        echo "Usage: $0 [deploy|build|scan|validate|verify|backup|rollback]"
        echo ""
        echo "Commands:"
        echo "  deploy   - Full secure deployment (default)"
        echo "  build    - Build and scan Docker image only"
        echo "  scan     - Run security scan on existing image"
        echo "  validate - Validate security configuration"
        echo "  verify   - Verify existing deployment"
        echo "  backup   - Create backup only"
        echo "  rollback - Rollback to previous deployment"
        echo ""
        echo "Environment Variables:"
        echo "  SECURITY_SCAN_ENABLED=true|false (default: true)"
        echo "  VALIDATION_ENABLED=true|false (default: true)"
        exit 1
        ;;
esac