#!/bin/bash
# Health Monitoring Script for Proxmox MCP Server
# This script monitors the deployment and provides health status

set -euo pipefail

# Configuration
DEPLOY_DIR="/opt/proxmox-mcp"
SERVICE_NAME="proxmox-mcp"
LOG_FILE="/var/log/proxmox-mcp-monitor.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}$message${NC}"
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    local message="[WARNING] $1"
    echo -e "${YELLOW}$message${NC}"
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    local message="[ERROR] $1"
    echo -e "${RED}$message${NC}"
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

info() {
    local message="[INFO] $1"
    echo -e "${BLUE}$message${NC}"
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

# Check if containers are running
check_containers() {
    local status="healthy"
    local details=""
    
    if [[ ! -d "$DEPLOY_DIR" ]]; then
        error "❌ Deployment directory not found: $DEPLOY_DIR"
        return 1
    fi
    
    cd "$DEPLOY_DIR"
    
    # Check if docker-compose.yml exists
    if [[ ! -f "docker-compose.yml" ]]; then
        error "❌ docker-compose.yml not found in $DEPLOY_DIR"
        return 1
    fi
    
    # Get container status
    local containers=$(docker-compose ps -q 2>/dev/null || echo "")
    if [[ -z "$containers" ]]; then
        error "❌ No containers found"
        return 1
    fi
    
    # Check each container
    while read -r container_id; do
        if [[ -n "$container_id" ]]; then
            local container_name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^.//')
            local container_status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
            local container_health=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")
            
            if [[ "$container_status" == "running" ]]; then
                if [[ "$container_health" == "healthy" ]] || [[ "$container_health" == "none" ]]; then
                    log "✅ $container_name: running"
                else
                    warn "⚠️  $container_name: running but unhealthy ($container_health)"
                    status="degraded"
                fi
            else
                error "❌ $container_name: $container_status"
                status="unhealthy"
            fi
        fi
    done <<< "$containers"
    
    if [[ "$status" == "healthy" ]]; then
        log "✅ All containers are healthy"
        return 0
    elif [[ "$status" == "degraded" ]]; then
        warn "⚠️  Some containers are degraded"
        return 1
    else
        error "❌ Containers are unhealthy"
        return 2
    fi
}

# Check service endpoints
check_endpoints() {
    local endpoints_ok=true
    
    # Check reverse proxy (port 80)
    if curl -f -s --max-time 10 http://localhost/docs > /dev/null; then
        log "✅ Reverse proxy (port 80): accessible"
    else
        error "❌ Reverse proxy (port 80): not accessible"
        endpoints_ok=false
    fi
    
    # Check direct MCP server (port 8080)
    if curl -f -s --max-time 10 http://localhost:8080/docs > /dev/null; then
        log "✅ Direct MCP server (port 8080): accessible"
    else
        error "❌ Direct MCP server (port 8080): not accessible"
        endpoints_ok=false
    fi
    
    # Check health endpoint (may return unhealthy but should respond)
    local health_response=$(curl -s --max-time 10 http://localhost/health 2>/dev/null || echo "no response")
    if [[ "$health_response" != "no response" ]]; then
        log "✅ Health endpoint: responding"
        info "Health status: $health_response"
    else
        error "❌ Health endpoint: not responding"
        endpoints_ok=false
    fi
    
    if $endpoints_ok; then
        log "✅ All endpoints are accessible"
        return 0
    else
        error "❌ Some endpoints are not accessible"
        return 1
    fi
}

# Check resource usage
check_resources() {
    if [[ ! -d "$DEPLOY_DIR" ]]; then
        warn "Cannot check resources - deployment directory not found"
        return 1
    fi
    
    cd "$DEPLOY_DIR"
    
    info "Resource usage:"
    
    # Get container resource usage
    local containers=$(docker-compose ps -q 2>/dev/null || echo "")
    if [[ -n "$containers" ]]; then
        while read -r container_id; do
            if [[ -n "$container_id" ]]; then
                local name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^.//')
                local stats=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" "$container_id" 2>/dev/null | tail -n 1)
                info "  $name: $stats"
            fi
        done <<< "$containers"
    fi
    
    # System resources
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    local disk_usage=$(df -h "$DEPLOY_DIR" | awk 'NR==2{print $5}')
    
    info "  System CPU: ${cpu_usage}%"
    info "  System Memory: ${mem_usage}%"
    info "  Disk usage: $disk_usage"
}

# Show service logs
show_logs() {
    if [[ ! -d "$DEPLOY_DIR" ]]; then
        error "Deployment directory not found: $DEPLOY_DIR"
        return 1
    fi
    
    cd "$DEPLOY_DIR"
    
    local lines="${1:-50}"
    info "Showing last $lines lines of logs:"
    docker-compose logs --tail="$lines" || error "Failed to get logs"
}

# Restart services
restart_services() {
    if [[ ! -d "$DEPLOY_DIR" ]]; then
        error "Deployment directory not found: $DEPLOY_DIR"
        return 1
    fi
    
    info "Restarting services..."
    cd "$DEPLOY_DIR"
    
    docker-compose restart || error "Failed to restart services"
    
    # Wait a moment for services to start
    sleep 5
    
    log "✅ Services restarted"
}

# Auto-heal function
auto_heal() {
    log "🔧 Starting auto-heal process..."
    
    # First try a simple restart
    if restart_services; then
        sleep 10
        if check_containers && check_endpoints; then
            log "✅ Auto-heal successful - services recovered"
            return 0
        fi
    fi
    
    # If restart didn't work, try recreating containers
    warn "Restart didn't work, trying to recreate containers..."
    cd "$DEPLOY_DIR"
    
    docker-compose down --timeout 30
    docker-compose up -d --remove-orphans
    
    sleep 15
    
    if check_containers && check_endpoints; then
        log "✅ Auto-heal successful - containers recreated"
        return 0
    else
        error "❌ Auto-heal failed - manual intervention required"
        return 1
    fi
}

# Full health check
full_health_check() {
    log "🔍 Starting comprehensive health check..."
    
    local overall_status="healthy"
    
    # Check containers
    if ! check_containers; then
        overall_status="unhealthy"
    fi
    
    # Check endpoints
    if ! check_endpoints; then
        overall_status="unhealthy"
    fi
    
    # Show resources
    check_resources
    
    echo ""
    if [[ "$overall_status" == "healthy" ]]; then
        log "🎉 Overall status: HEALTHY"
        return 0
    else
        error "💥 Overall status: UNHEALTHY"
        return 1
    fi
}

# Watch mode - continuous monitoring
watch_mode() {
    local interval="${1:-60}"
    log "👀 Starting watch mode (checking every ${interval}s)..."
    log "Press Ctrl+C to stop"
    
    while true; do
        echo "$(date +'%Y-%m-%d %H:%M:%S') - Health Check"
        echo "=================================="
        
        if full_health_check; then
            echo "✅ Status: OK"
        else
            echo "❌ Status: ISSUES DETECTED"
            warn "Issues detected - consider running auto-heal"
        fi
        
        echo ""
        sleep "$interval"
    done
}

# Main function
main() {
    case "${1:-check}" in
        "check"|"status")
            full_health_check
            ;;
        "containers")
            check_containers
            ;;
        "endpoints")
            check_endpoints
            ;;
        "resources")
            check_resources
            ;;
        "logs")
            show_logs "${2:-50}"
            ;;
        "restart")
            restart_services
            ;;
        "heal")
            auto_heal
            ;;
        "watch")
            watch_mode "${2:-60}"
            ;;
        *)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  check      - Full health check (default)"
            echo "  status     - Same as check"
            echo "  containers - Check container status only"
            echo "  endpoints  - Check service endpoints only"
            echo "  resources  - Show resource usage"
            echo "  logs [n]   - Show last n lines of logs (default: 50)"
            echo "  restart    - Restart all services"
            echo "  heal       - Auto-heal services (restart/recreate)"
            echo "  watch [s]  - Continuous monitoring (default: 60s interval)"
            echo ""
            echo "Examples:"
            echo "  $0                  # Quick health check"
            echo "  $0 logs 100         # Show last 100 log lines"
            echo "  $0 watch 30         # Monitor every 30 seconds"
            exit 1
            ;;
    esac
}

# Ensure log file directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Run main function
main "$@"