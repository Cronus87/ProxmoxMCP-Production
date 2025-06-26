#!/bin/bash

# PROXMOX MCP UPDATE MANAGEMENT SYSTEM
# ====================================
# Comprehensive update mechanism for maintaining Proxmox MCP installations
# Provides safe, rollback-capable updates with validation and monitoring
#
# FEATURES:
# - Automated update detection and deployment
# - Configuration migration and validation
# - Service health monitoring during updates
# - Automatic rollback on failure
# - Security configuration updates
# - Container image management

set -euo pipefail

# ==============================================================================
# UPDATE SYSTEM CONFIGURATION
# ==============================================================================

readonly UPDATE_VERSION="1.0.0"
readonly INSTALL_ROOT="/opt/proxmox-mcp"
readonly BACKUP_ROOT="/opt/proxmox-mcp-backups"
readonly UPDATE_LOG="/var/log/proxmox-mcp-updates.log"
readonly SERVICE_NAME="proxmox-mcp"

# Update sources
readonly GITHUB_REPO="your-username/ProxmoxMCP-Production"
readonly CONTAINER_REGISTRY="ghcr.io/your-username/fullproxmoxmcp"
readonly UPDATE_CHECK_URL="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

# Update configuration
readonly MAX_BACKUP_RETENTION=10
readonly UPDATE_TIMEOUT=1800  # 30 minutes
readonly HEALTH_CHECK_RETRIES=30
readonly HEALTH_CHECK_INTERVAL=10

# ==============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# ==============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp]${NC} ${BOLD}[$level]${NC} $message" | tee -a "$UPDATE_LOG"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}✅ $*${NC}"; }
warning() { log "WARNING" "${YELLOW}⚠️  $*${NC}"; }
error() { log "ERROR" "${RED}❌ $*${NC}"; }
critical() { log "CRITICAL" "${RED}🚨 $*${NC}"; exit 1; }

update_header() {
    local operation="$1"
    local description="$2"
    echo ""
    echo "=============================================="
    echo -e "${PURPLE}${BOLD}UPDATE: $operation${NC}"
    echo "=============================================="
    echo -e "${CYAN}$description${NC}"
    echo ""
}

# ==============================================================================
# VERSION MANAGEMENT
# ==============================================================================

get_current_version() {
    if [[ -f "$INSTALL_ROOT/VERSION" ]]; then
        cat "$INSTALL_ROOT/VERSION"
    else
        echo "unknown"
    fi
}

get_latest_version() {
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        local latest_release
        latest_release=$(curl -s "$UPDATE_CHECK_URL" 2>/dev/null)
        if [[ $? -eq 0 ]] && echo "$latest_release" | jq -e '.tag_name' >/dev/null 2>&1; then
            echo "$latest_release" | jq -r '.tag_name'
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

compare_versions() {
    local current="$1"
    local latest="$2"
    
    if [[ "$current" == "unknown" ]] || [[ "$latest" == "unknown" ]]; then
        return 2  # Cannot compare
    fi
    
    # Remove 'v' prefix if present
    current="${current#v}"
    latest="${latest#v}"
    
    if [[ "$current" == "$latest" ]]; then
        return 0  # Equal
    fi
    
    # Simple version comparison (works for semantic versioning)
    if printf '%s\n%s\n' "$current" "$latest" | sort -V | head -1 | grep -q "^$current$"; then
        return 1  # Current is older
    else
        return -1  # Current is newer (shouldn't happen in normal operation)
    fi
}

# ==============================================================================
# BACKUP MANAGEMENT
# ==============================================================================

create_update_backup() {
    local backup_id="$1"
    local backup_path="$BACKUP_ROOT/update-backup-$backup_id"
    
    info "Creating update backup..."
    
    mkdir -p "$BACKUP_ROOT"
    
    if [[ -d "$INSTALL_ROOT" ]]; then
        # Stop services before backup
        systemctl stop "$SERVICE_NAME" || warning "Service was not running"
        
        # Create comprehensive backup
        cp -r "$INSTALL_ROOT" "$backup_path"
        
        # Backup systemd service file
        if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
            cp "/etc/systemd/system/$SERVICE_NAME.service" "$backup_path/systemd-service.backup"
        fi
        
        # Backup sudoers configuration
        if [[ -f "/etc/sudoers.d/claude-user" ]]; then
            cp "/etc/sudoers.d/claude-user" "$backup_path/sudoers.backup"
        fi
        
        # Create backup manifest
        create_backup_manifest "$backup_path"
        
        success "Update backup created: $backup_path"
        
        # Restart services
        systemctl start "$SERVICE_NAME" || warning "Failed to restart service"
        
        # Cleanup old backups
        cleanup_old_backups
        
        return 0
    else
        error "Installation directory not found: $INSTALL_ROOT"
        return 1
    fi
}

create_backup_manifest() {
    local backup_path="$1"
    local manifest_file="$backup_path/backup-manifest.json"
    
    cat > "$manifest_file" << EOF
{
  "backup_timestamp": "$(date -Iseconds)",
  "backup_type": "update",
  "source_version": "$(get_current_version)",
  "installation_root": "$INSTALL_ROOT",
  "service_name": "$SERVICE_NAME",
  "files": {
    "environment": "$(test -f "$INSTALL_ROOT/.env" && echo "present" || echo "missing")",
    "docker_compose": "$(test -f "$INSTALL_ROOT/docker-compose.yml" && echo "present" || echo "missing")",
    "caddy_config": "$(test -f "$INSTALL_ROOT/caddy/Caddyfile" && echo "present" || echo "missing")",
    "ssh_keys": "$(test -f "$INSTALL_ROOT/keys/claude_proxmox_key" && echo "present" || echo "missing")",
    "systemd_service": "$(test -f "/etc/systemd/system/$SERVICE_NAME.service" && echo "present" || echo "missing")",
    "sudoers_config": "$(test -f "/etc/sudoers.d/claude-user" && echo "present" || echo "missing")"
  },
  "container_images": $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(proxmox-mcp|mcp-)" | jq -R . | jq -s . || echo "[]"),
  "running_containers": $(docker ps --format "{{.Names}}" | grep -E "(proxmox-mcp|mcp-)" | jq -R . | jq -s . || echo "[]")
}
EOF
}

cleanup_old_backups() {
    local backup_count
    backup_count=$(find "$BACKUP_ROOT" -maxdepth 1 -name "update-backup-*" -type d | wc -l)
    
    if [[ $backup_count -gt $MAX_BACKUP_RETENTION ]]; then
        info "Cleaning up old backups (keeping latest $MAX_BACKUP_RETENTION)..."
        find "$BACKUP_ROOT" -maxdepth 1 -name "update-backup-*" -type d -printf '%T+ %p\n' | \
            sort -r | tail -n +$((MAX_BACKUP_RETENTION + 1)) | cut -d' ' -f2- | \
            xargs -r rm -rf
        success "Old backups cleaned up"
    fi
}

# ==============================================================================
# UPDATE DETECTION AND MANAGEMENT
# ==============================================================================

check_for_updates() {
    update_header "CHECK" "Checking for available updates"
    
    local current_version
    local latest_version
    
    current_version=$(get_current_version)
    latest_version=$(get_latest_version)
    
    info "Current version: $current_version"
    info "Latest version: $latest_version"
    
    if compare_versions "$current_version" "$latest_version"; then
        case $? in
            0)
                success "Installation is up to date"
                return 0
                ;;
            1)
                warning "Update available: $current_version → $latest_version"
                return 1
                ;;
            2)
                warning "Unable to determine version status"
                return 2
                ;;
        esac
    fi
}

download_update() {
    local version="$1"
    local download_dir="$2"
    
    info "Downloading update version: $version"
    
    mkdir -p "$download_dir"
    
    # Download release archive
    local download_url="https://github.com/$GITHUB_REPO/archive/refs/tags/$version.tar.gz"
    local archive_file="$download_dir/update-$version.tar.gz"
    
    if curl -L -o "$archive_file" "$download_url"; then
        # Extract archive
        tar -xzf "$archive_file" -C "$download_dir" --strip-components=1
        rm "$archive_file"
        
        success "Update downloaded successfully"
        return 0
    else
        error "Failed to download update"
        return 1
    fi
}

# ==============================================================================
# CONFIGURATION MIGRATION
# ==============================================================================

migrate_configuration() {
    local old_config="$1"
    local new_config_template="$2"
    local output_config="$3"
    
    info "Migrating configuration..."
    
    if [[ ! -f "$old_config" ]]; then
        warning "Old configuration not found, using template"
        cp "$new_config_template" "$output_config"
        return 0
    fi
    
    # Create backup of old config
    cp "$old_config" "${old_config}.backup-$(date +%Y%m%d-%H%M%S)"
    
    # Load old configuration values
    declare -A old_values
    while IFS='=' read -r key value; do
        if [[ ! "$key" =~ ^# ]] && [[ -n "$key" ]]; then
            old_values["$key"]="$value"
        fi
    done < "$old_config"
    
    # Process new template with old values
    if [[ -f "$new_config_template" ]]; then
        cp "$new_config_template" "$output_config"
        
        # Replace values in new config
        for key in "${!old_values[@]}"; do
            local value="${old_values[$key]}"
            if grep -q "^$key=" "$output_config"; then
                sed -i "s|^$key=.*|$key=$value|" "$output_config"
            fi
        done
        
        success "Configuration migrated successfully"
        return 0
    else
        error "New configuration template not found"
        return 1
    fi
}

validate_migrated_config() {
    local config_file="$1"
    
    info "Validating migrated configuration..."
    
    # Check required parameters
    local required_params=("PROXMOX_HOST" "SSH_USER" "PROXMOX_TOKEN_VALUE")
    for param in "${required_params[@]}"; do
        if ! grep -q "^$param=" "$config_file"; then
            error "Required parameter missing after migration: $param"
            return 1
        fi
    done
    
    # Validate Docker Compose file if it exists
    if [[ -f "$INSTALL_ROOT/docker-compose.yml" ]]; then
        if ! docker-compose -f "$INSTALL_ROOT/docker-compose.yml" config >/dev/null 2>&1; then
            error "Docker Compose configuration is invalid after migration"
            return 1
        fi
    fi
    
    success "Migrated configuration validated"
    return 0
}

# ==============================================================================
# SERVICE UPDATE MANAGEMENT
# ==============================================================================

update_container_images() {
    local version="$1"
    
    info "Updating container images to version: $version"
    
    cd "$INSTALL_ROOT"
    
    # Update image tag in environment
    if [[ -f ".env" ]]; then
        sed -i "s/IMAGE_TAG=.*/IMAGE_TAG=$version/" .env
    fi
    
    # Pull new images
    if docker-compose pull; then
        success "Container images updated"
        return 0
    else
        error "Failed to update container images"
        return 1
    fi
}

perform_rolling_update() {
    local version="$1"
    
    info "Performing rolling update to version: $version"
    
    cd "$INSTALL_ROOT"
    
    # Update containers one by one with health checks
    local services=("mcp-server" "caddy")
    
    for service in "${services[@]}"; do
        info "Updating service: $service"
        
        # Update specific service
        if docker-compose up -d --no-deps "$service"; then
            # Wait for service to be healthy
            if wait_for_service_health "$service"; then
                success "Service $service updated successfully"
            else
                error "Service $service failed health check after update"
                return 1
            fi
        else
            error "Failed to update service: $service"
            return 1
        fi
    done
    
    # Update monitoring services if enabled
    if docker-compose --profile monitoring ps | grep -q "Up"; then
        info "Updating monitoring services..."
        docker-compose --profile monitoring up -d
    fi
    
    success "Rolling update completed"
}

wait_for_service_health() {
    local service="$1"
    local retries=0
    
    while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
        if docker-compose ps "$service" | grep -q "Up (healthy)"; then
            return 0
        fi
        
        ((retries++))
        info "Waiting for $service to be healthy... ($retries/$HEALTH_CHECK_RETRIES)"
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    return 1
}

# ==============================================================================
# SECURITY UPDATE MANAGEMENT
# ==============================================================================

update_security_configuration() {
    local update_dir="$1"
    
    info "Updating security configuration..."
    
    # Check if new security configuration exists (now generated inline by install.sh)
    local new_sudoers="$update_dir/claude-user-practical-admin-sudoers"
    if [[ -f "$new_sudoers" ]]; then
        # Backup current sudoers
        if [[ -f "/etc/sudoers.d/claude-user" ]]; then
            cp "/etc/sudoers.d/claude-user" "/etc/sudoers.d/claude-user.backup-$(date +%Y%m%d-%H%M%S)"
        fi
        
        # Deploy new practical admin configuration
        cp "$new_sudoers" "/etc/sudoers.d/claude-user"
        chmod 440 "/etc/sudoers.d/claude-user"
        
        # Validate sudoers syntax
        if visudo -c; then
            success "Security configuration updated"
            
            # Run security validation if available
            if [[ -f "$update_dir/comprehensive-security-validation.sh" ]]; then
                info "Running security validation..."
                chmod +x "$update_dir/comprehensive-security-validation.sh"
                if sudo -u claude-user "$update_dir/comprehensive-security-validation.sh"; then
                    success "Security validation passed"
                else
                    warning "Security validation completed with warnings"
                fi
            fi
        else
            error "Invalid sudoers configuration - rolling back"
            if [[ -f "/etc/sudoers.d/claude-user.backup-$(date +%Y%m%d)" ]]; then
                cp "/etc/sudoers.d/claude-user.backup-$(date +%Y%m%d)" "/etc/sudoers.d/claude-user"
            fi
            return 1
        fi
    fi
}

# ==============================================================================
# ROLLBACK MANAGEMENT
# ==============================================================================

perform_rollback() {
    local backup_path="$1"
    local reason="${2:-manual}"
    
    update_header "ROLLBACK" "Rolling back update due to: $reason"
    
    if [[ ! -d "$backup_path" ]]; then
        critical "Backup directory not found: $backup_path"
    fi
    
    # Stop current services
    systemctl stop "$SERVICE_NAME" || true
    cd "$INSTALL_ROOT" && docker-compose down || true
    
    # Restore installation directory
    if [[ -d "$INSTALL_ROOT" ]]; then
        mv "$INSTALL_ROOT" "${INSTALL_ROOT}.failed-$(date +%Y%m%d-%H%M%S)"
    fi
    cp -r "$backup_path" "$INSTALL_ROOT"
    
    # Restore systemd service
    if [[ -f "$backup_path/systemd-service.backup" ]]; then
        cp "$backup_path/systemd-service.backup" "/etc/systemd/system/$SERVICE_NAME.service"
        systemctl daemon-reload
    fi
    
    # Restore sudoers configuration
    if [[ -f "$backup_path/sudoers.backup" ]]; then
        cp "$backup_path/sudoers.backup" "/etc/sudoers.d/claude-user"
    fi
    
    # Restart services
    cd "$INSTALL_ROOT"
    docker-compose up -d
    systemctl start "$SERVICE_NAME"
    
    # Verify rollback
    if wait_for_service_health "mcp-server"; then
        success "Rollback completed successfully"
        return 0
    else
        critical "Rollback failed - manual intervention required"
    fi
}

# ==============================================================================
# MAIN UPDATE FUNCTIONS
# ==============================================================================

perform_update() {
    local target_version="$1"
    local force_update="${2:-false}"
    
    update_header "UPDATE" "Updating to version: $target_version"
    
    # Pre-update checks
    if [[ "$force_update" != "true" ]]; then
        local current_version
        current_version=$(get_current_version)
        
        if ! compare_versions "$current_version" "$target_version"; then
            case $? in
                0)
                    success "Already at target version: $target_version"
                    return 0
                    ;;
                -1)
                    warning "Current version is newer than target version"
                    read -p "Continue with downgrade? (y/N): " -r
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        return 0
                    fi
                    ;;
            esac
        fi
    fi
    
    # Create backup
    local backup_id="$(date +%Y%m%d-%H%M%S)-$target_version"
    if ! create_update_backup "$backup_id"; then
        critical "Failed to create backup - aborting update"
    fi
    
    # Download update
    local update_dir="/tmp/proxmox-mcp-update-$$"
    if ! download_update "$target_version" "$update_dir"; then
        critical "Failed to download update"
    fi
    
    # Perform update with automatic rollback on failure
    if perform_update_steps "$update_dir" "$target_version" "$backup_id"; then
        success "Update completed successfully"
        cleanup_update_files "$update_dir"
        return 0
    else
        error "Update failed - performing automatic rollback"
        perform_rollback "$BACKUP_ROOT/update-backup-$backup_id" "update failure"
        cleanup_update_files "$update_dir"
        return 1
    fi
}

perform_update_steps() {
    local update_dir="$1"
    local version="$2"
    local backup_id="$3"
    
    # Step 1: Migrate configuration
    if [[ -f "$update_dir/.env.example" ]]; then
        if ! migrate_configuration "$INSTALL_ROOT/.env" "$update_dir/.env.example" "$INSTALL_ROOT/.env.new"; then
            return 1
        fi
        mv "$INSTALL_ROOT/.env.new" "$INSTALL_ROOT/.env"
    fi
    
    # Step 2: Update Docker Compose configuration
    if [[ -f "$update_dir/docker/docker-compose.prod.yml" ]]; then
        cp "$update_dir/docker/docker-compose.prod.yml" "$INSTALL_ROOT/docker-compose.yml"
    fi
    
    # Step 3: Update Caddy configuration
    if [[ -f "$update_dir/caddy/Caddyfile" ]]; then
        cp "$update_dir/caddy/Caddyfile" "$INSTALL_ROOT/caddy/Caddyfile"
    fi
    
    # Step 4: Validate configuration
    if ! validate_migrated_config "$INSTALL_ROOT/.env"; then
        return 1
    fi
    
    # Step 5: Update security configuration
    if ! update_security_configuration "$update_dir"; then
        return 1
    fi
    
    # Step 6: Update container images
    if ! update_container_images "$version"; then
        return 1
    fi
    
    # Step 7: Perform rolling update
    if ! perform_rolling_update "$version"; then
        return 1
    fi
    
    # Step 8: Update version file
    echo "$version" > "$INSTALL_ROOT/VERSION"
    
    # Step 9: Final health check
    if ! wait_for_service_health "mcp-server"; then
        return 1
    fi
    
    return 0
}

cleanup_update_files() {
    local update_dir="$1"
    
    if [[ -d "$update_dir" ]]; then
        rm -rf "$update_dir"
    fi
}

# ==============================================================================
# AUTOMATED UPDATE MANAGEMENT
# ==============================================================================

setup_automated_updates() {
    local schedule="${1:-weekly}"  # daily, weekly, monthly
    
    update_header "AUTOMATION" "Setting up automated updates: $schedule"
    
    # Create update script
    local update_script="/usr/local/bin/proxmox-mcp-auto-update"
    cat > "$update_script" << 'EOF'
#!/bin/bash
# Automated Proxmox MCP Update Script

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
UPDATE_MANAGER="/opt/proxmox-mcp/update-manager.sh"

if [[ -f "$UPDATE_MANAGER" ]]; then
    "$UPDATE_MANAGER" auto-update
else
    echo "Update manager not found: $UPDATE_MANAGER"
    exit 1
fi
EOF
    chmod +x "$update_script"
    
    # Create systemd service
    cat > "/etc/systemd/system/proxmox-mcp-auto-update.service" << EOF
[Unit]
Description=Proxmox MCP Automated Update
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$update_script
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Create systemd timer
    local timer_schedule
    case "$schedule" in
        "daily")
            timer_schedule="daily"
            ;;
        "weekly")
            timer_schedule="weekly"
            ;;
        "monthly")
            timer_schedule="monthly"
            ;;
        *)
            timer_schedule="weekly"
            ;;
    esac
    
    cat > "/etc/systemd/system/proxmox-mcp-auto-update.timer" << EOF
[Unit]
Description=Proxmox MCP Automated Update Timer
Requires=proxmox-mcp-auto-update.service

[Timer]
OnCalendar=$timer_schedule
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    systemctl daemon-reload
    systemctl enable proxmox-mcp-auto-update.timer
    systemctl start proxmox-mcp-auto-update.timer
    
    success "Automated updates configured: $schedule"
    systemctl status proxmox-mcp-auto-update.timer --no-pager
}

perform_auto_update() {
    info "Performing automated update check..."
    
    if check_for_updates; then
        case $? in
            0)
                info "No updates available"
                return 0
                ;;
            1)
                local latest_version
                latest_version=$(get_latest_version)
                warning "Performing automated update to: $latest_version"
                
                if perform_update "$latest_version"; then
                    success "Automated update completed successfully"
                    return 0
                else
                    error "Automated update failed"
                    return 1
                fi
                ;;
            2)
                warning "Unable to check for updates"
                return 1
                ;;
        esac
    fi
}

# ==============================================================================
# COMMAND LINE INTERFACE
# ==============================================================================

show_help() {
    cat << EOF
Proxmox MCP Update Manager v$UPDATE_VERSION

Usage: $0 [command] [options]

Commands:
  check                    Check for available updates
  update [version]         Update to specific version (latest if not specified)
  rollback [backup_id]     Rollback to previous backup
  list-backups             List available backups
  setup-auto [schedule]    Setup automated updates (daily/weekly/monthly)
  auto-update              Perform automated update (used by scheduler)
  status                   Show current installation status

Options:
  --force                  Force update even if versions are equal
  --help                   Show this help message
  --version                Show version information

Examples:
  $0 check
  $0 update v1.2.0
  $0 update --force
  $0 rollback update-backup-20231125-143022-v1.1.0
  $0 setup-auto weekly
  $0 status

EOF
}

show_status() {
    update_header "STATUS" "Current installation status"
    
    local current_version
    current_version=$(get_current_version)
    
    echo -e "${BLUE}Version Information:${NC}"
    echo -e "  Current Version: ${GREEN}$current_version${NC}"
    
    local latest_version
    latest_version=$(get_latest_version)
    if [[ "$latest_version" != "unknown" ]]; then
        echo -e "  Latest Version: ${GREEN}$latest_version${NC}"
        
        if compare_versions "$current_version" "$latest_version"; then
            case $? in
                0)
                    echo -e "  Status: ${GREEN}Up to date${NC}"
                    ;;
                1)
                    echo -e "  Status: ${YELLOW}Update available${NC}"
                    ;;
                2)
                    echo -e "  Status: ${YELLOW}Cannot determine${NC}"
                    ;;
            esac
        fi
    fi
    
    echo ""
    echo -e "${BLUE}Service Status:${NC}"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  Service: ${GREEN}Active${NC}"
    else
        echo -e "  Service: ${RED}Inactive${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Container Status:${NC}"
    cd "$INSTALL_ROOT" && docker-compose ps 2>/dev/null || echo "  Docker Compose not available"
    
    echo ""
    echo -e "${BLUE}Available Backups:${NC}"
    local backup_count
    backup_count=$(find "$BACKUP_ROOT" -maxdepth 1 -name "update-backup-*" -type d 2>/dev/null | wc -l)
    echo -e "  Backup Count: ${GREEN}$backup_count${NC}"
    
    if [[ $backup_count -gt 0 ]]; then
        echo -e "  Latest Backup: ${GREEN}$(find "$BACKUP_ROOT" -maxdepth 1 -name "update-backup-*" -type d -printf '%T+ %f\n' 2>/dev/null | sort -r | head -1 | cut -d' ' -f2-)${NC}"
    fi
}

list_backups() {
    update_header "BACKUPS" "Available update backups"
    
    if [[ ! -d "$BACKUP_ROOT" ]]; then
        warning "Backup directory not found: $BACKUP_ROOT"
        return 1
    fi
    
    local backups
    backups=$(find "$BACKUP_ROOT" -maxdepth 1 -name "update-backup-*" -type d -printf '%T+ %f\n' 2>/dev/null | sort -r)
    
    if [[ -z "$backups" ]]; then
        info "No backups found"
        return 0
    fi
    
    echo -e "${BLUE}Backup ID${NC}                           ${BLUE}Created${NC}                 ${BLUE}Size${NC}"
    echo "----------------------------------------------------------------"
    
    while IFS=' ' read -r timestamp backup_id; do
        local backup_path="$BACKUP_ROOT/$backup_id"
        local size
        size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
        local created
        created=$(echo "$timestamp" | cut -d'T' -f1)
        
        printf "%-35s %-20s %s\n" "$backup_id" "$created" "$size"
    done <<< "$backups"
}

main() {
    # Initialize logging
    mkdir -p "$(dirname "$UPDATE_LOG")"
    touch "$UPDATE_LOG"
    
    local command="${1:-help}"
    local force_flag=false
    
    # Parse global options
    for arg in "$@"; do
        case "$arg" in
            "--force")
                force_flag=true
                ;;
        esac
    done
    
    case "$command" in
        "check")
            check_for_updates
            ;;
        "update")
            local target_version="${2:-$(get_latest_version)}"
            if [[ "$target_version" == "unknown" ]]; then
                critical "Cannot determine target version"
            fi
            perform_update "$target_version" "$force_flag"
            ;;
        "rollback")
            local backup_id="${2:-}"
            if [[ -z "$backup_id" ]]; then
                list_backups
                read -p "Enter backup ID to rollback to: " -r backup_id
            fi
            
            if [[ -n "$backup_id" ]]; then
                perform_rollback "$BACKUP_ROOT/$backup_id" "manual"
            else
                error "No backup ID specified"
                exit 1
            fi
            ;;
        "list-backups")
            list_backups
            ;;
        "setup-auto")
            local schedule="${2:-weekly}"
            setup_automated_updates "$schedule"
            ;;
        "auto-update")
            perform_auto_update
            ;;
        "status")
            show_status
            ;;
        "--help"|"help")
            show_help
            ;;
        "--version")
            echo "Proxmox MCP Update Manager v$UPDATE_VERSION"
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi