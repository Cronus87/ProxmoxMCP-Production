#!/bin/bash
# Update System Script for Proxmox MCP Server
# This script handles updates from git repository and rebuilds/redeploys

set -euo pipefail

# Configuration
DEPLOY_DIR="/opt/proxmox-mcp"
BACKUP_DIR="/opt/proxmox-mcp-backups"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
    fi
    
    if ! command -v git &> /dev/null; then
        error "Git is not installed"
    fi
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi
    
    if [[ ! -d "$REPO_DIR" ]]; then
        error "Repository directory not found: $REPO_DIR"
    fi
    
    log "✅ Prerequisites check passed"
}

# Update code from repository
update_code() {
    log "Updating code from repository..."
    
    cd "$REPO_DIR"
    
    # Store current branch and commit
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    info "Current branch: $current_branch"
    info "Current commit: $current_commit"
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warn "⚠️  Uncommitted changes detected. Stashing..."
        git stash push -m "Auto-stash before update $(date)"
    fi
    
    # Fetch latest changes
    git fetch origin
    
    # Get latest commit on current branch
    local latest_commit=$(git rev-parse --short origin/$current_branch 2>/dev/null || echo "unknown")
    
    if [[ "$current_commit" == "$latest_commit" ]]; then
        log "✅ Already up to date (commit: $current_commit)"
        return 0
    fi
    
    # Pull latest changes
    info "Updating from $current_commit to $latest_commit..."
    git pull origin "$current_branch"
    
    local new_commit=$(git rev-parse --short HEAD)
    log "✅ Code updated to commit: $new_commit"
    
    # Show what changed
    info "Changes since last update:"
    git log --oneline "$current_commit..$new_commit" || true
}

# Build new image with update tag
build_updated_image() {
    log "Building updated Docker image..."
    
    cd "$REPO_DIR"
    
    # Generate build metadata
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local version=$(cat VERSION 2>/dev/null || echo "dev")
    local vcs_ref=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local update_tag="update-$(date +%Y%m%d_%H%M%S)"
    
    info "Build metadata:"
    info "  Date: $build_date"
    info "  Version: $version"
    info "  VCS Ref: $vcs_ref"
    info "  Update Tag: $update_tag"
    
    # Build new image with update tag
    docker build \
        -f docker/Dockerfile.prod \
        -t "$IMAGE_NAME:$update_tag" \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg VERSION="$version" \
        --build-arg VCS_REF="$vcs_ref" \
        .
    
    log "✅ Updated image built: $IMAGE_NAME:$update_tag"
    echo "$update_tag" > /tmp/mcp_update_tag
}

# Test new image before deployment
test_image() {
    local update_tag="$1"
    log "Testing new image: $IMAGE_NAME:$update_tag"
    
    # Create temporary test container
    local test_container="mcp-test-$(date +%s)"
    
    info "Starting test container..."
    docker run -d \
        --name "$test_container" \
        --network bridge \
        -p 18080:8080 \
        -e PROXMOX_HOST=localhost \
        -e LOG_LEVEL=INFO \
        "$IMAGE_NAME:$update_tag" || {
        error "Failed to start test container"
        return 1
    }
    
    # Wait for container to start
    sleep 10
    
    # Test if container is responding
    local test_success=false
    for i in {1..10}; do
        if curl -f -s --max-time 5 http://localhost:18080/docs > /dev/null; then
            test_success=true
            break
        fi
        sleep 2
    done
    
    # Cleanup test container
    docker stop "$test_container" >/dev/null 2>&1 || true
    docker rm "$test_container" >/dev/null 2>&1 || true
    
    if $test_success; then
        log "✅ Image test passed"
        return 0
    else
        error "❌ Image test failed"
        return 1
    fi
}

# Deploy updated image
deploy_update() {
    local update_tag="$1"
    log "Deploying updated image..."
    
    if [[ ! -d "$DEPLOY_DIR" ]]; then
        error "Deployment directory not found: $DEPLOY_DIR"
    fi
    
    cd "$DEPLOY_DIR"
    
    # Update docker-compose.yml to use new image
    sed -i "s|$IMAGE_NAME:.*|$IMAGE_NAME:$update_tag|g" docker-compose.yml
    
    # Rolling update
    info "Performing rolling update..."
    docker-compose pull
    docker-compose up -d --remove-orphans
    
    # Wait for services to be ready
    local max_attempts=30
    local attempt=0
    
    info "Waiting for services to be ready..."
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f -s http://localhost/docs > /dev/null 2>&1; then
            log "✅ Services are ready after update"
            break
        fi
        
        ((attempt++))
        sleep 5
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error "❌ Services failed to become ready after update"
        return 1
    fi
    
    log "✅ Update deployment completed"
}

# Verify update success
verify_update() {
    log "Verifying update success..."
    
    # Use the monitoring script for verification
    if [[ -f "$REPO_DIR/deploy/monitor-health.sh" ]]; then
        "$REPO_DIR/deploy/monitor-health.sh" check
    else
        # Fallback verification
        if curl -f -s http://localhost/docs > /dev/null; then
            log "✅ Basic verification passed"
        else
            error "❌ Basic verification failed"
            return 1
        fi
    fi
}

# Cleanup old images
cleanup_old_images() {
    log "Cleaning up old images..."
    
    # Keep only the latest 3 images
    local old_images=$(docker images "$IMAGE_NAME" --format "{{.ID}}" | tail -n +4)
    
    if [[ -n "$old_images" ]]; then
        info "Removing old images..."
        echo "$old_images" | xargs docker rmi -f || warn "Some images couldn't be removed"
        log "✅ Old images cleaned up"
    else
        info "No old images to clean up"
    fi
}

# Rollback function
rollback_update() {
    warn "Rolling back update..."
    
    # Find the previous image
    local previous_image=$(docker images "$IMAGE_NAME" --format "{{.Tag}}" | grep -v latest | head -1)
    
    if [[ -n "$previous_image" ]]; then
        log "Rolling back to: $IMAGE_NAME:$previous_image"
        
        cd "$DEPLOY_DIR"
        sed -i "s|$IMAGE_NAME:.*|$IMAGE_NAME:$previous_image|g" docker-compose.yml
        docker-compose up -d --remove-orphans
        
        log "✅ Rollback completed"
    else
        error "No previous image found for rollback"
    fi
}

# Full update process
full_update() {
    log "🚀 Starting full update process..."
    
    # Create backup before update
    if [[ -f "$REPO_DIR/deploy/local-build-deploy.sh" ]]; then
        "$REPO_DIR/deploy/local-build-deploy.sh" backup
    fi
    
    # Update code
    update_code
    
    # Build updated image
    build_updated_image
    local update_tag=$(cat /tmp/mcp_update_tag)
    
    # Test new image
    if ! test_image "$update_tag"; then
        error "Image test failed - aborting update"
    fi
    
    # Deploy update
    if ! deploy_update "$update_tag"; then
        warn "Deployment failed - attempting rollback"
        rollback_update
        error "Update failed and rollback attempted"
    fi
    
    # Verify update
    if ! verify_update; then
        warn "Verification failed - attempting rollback"
        rollback_update
        error "Update verification failed and rollback attempted"
    fi
    
    # Cleanup
    cleanup_old_images
    
    log "🎉 Update completed successfully!"
    
    # Show update summary
    echo ""
    echo "📋 Update Summary:"
    echo "=================="
    echo "   Image: $IMAGE_NAME:$update_tag"
    echo "   Commit: $(git -C "$REPO_DIR" rev-parse --short HEAD)"
    echo "   Date: $(date)"
    echo ""
}

# Show current status
show_status() {
    info "Current deployment status:"
    
    if [[ -d "$DEPLOY_DIR" ]]; then
        cd "$DEPLOY_DIR"
        
        # Show current image
        local current_image=$(docker-compose config | grep "image:" | head -1 | awk '{print $2}')
        info "  Current image: $current_image"
        
        # Show container status
        info "  Container status:"
        docker-compose ps --format table
    else
        warn "No deployment found"
    fi
    
    # Show repository status
    if [[ -d "$REPO_DIR" ]]; then
        cd "$REPO_DIR"
        local current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        
        info "  Repository status:"
        info "    Branch: $current_branch"
        info "    Commit: $current_commit"
        
        # Check if updates are available
        git fetch origin >/dev/null 2>&1 || warn "Could not fetch from origin"
        local latest_commit=$(git rev-parse --short origin/$current_branch 2>/dev/null || echo "unknown")
        
        if [[ "$current_commit" != "$latest_commit" ]]; then
            warn "  📢 Updates available! ($current_commit -> $latest_commit)"
        else
            info "    Status: Up to date"
        fi
    fi
}

# Main function
main() {
    case "${1:-status}" in
        "update"|"full")
            check_prerequisites
            full_update
            ;;
        "code")
            check_prerequisites
            update_code
            ;;
        "build")
            check_prerequisites
            build_updated_image
            ;;
        "deploy")
            check_prerequisites
            local update_tag="${2:-$(cat /tmp/mcp_update_tag 2>/dev/null || echo "$IMAGE_TAG")}"
            deploy_update "$update_tag"
            ;;
        "test")
            check_prerequisites
            local update_tag="${2:-$(cat /tmp/mcp_update_tag 2>/dev/null || echo "$IMAGE_TAG")}"
            test_image "$update_tag"
            ;;
        "rollback")
            check_prerequisites
            rollback_update
            ;;
        "cleanup")
            check_prerequisites
            cleanup_old_images
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  update     - Full update process (code + build + deploy)"
            echo "  full       - Same as update"
            echo "  code       - Update code from repository only"
            echo "  build      - Build updated image only"
            echo "  deploy     - Deploy updated image only"
            echo "  test       - Test updated image only"
            echo "  rollback   - Rollback to previous version"
            echo "  cleanup    - Clean up old Docker images"
            echo "  status     - Show current status (default)"
            echo ""
            echo "Examples:"
            echo "  $0              # Show status"
            echo "  $0 update       # Full update process"
            echo "  $0 rollback     # Rollback if there are issues"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"