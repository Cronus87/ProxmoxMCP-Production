#!/bin/bash
# Docker Security Validation Script
# Validates security configuration of Docker containers and networks

set -euo pipefail

# Configuration
COMPOSE_FILE="${1:-docker-compose.secure.yml}"
VALIDATION_OUTPUT_DIR="./security-validation"

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
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Initialize validation
init_validation() {
    log "Initializing security validation..."
    mkdir -p "$VALIDATION_OUTPUT_DIR"
    
    # Create validation report
    cat > "$VALIDATION_OUTPUT_DIR/security-validation-report.md" << 'EOF'
# Docker Security Validation Report

**Generated:** $(date)
**Compose File:** $(basename "$COMPOSE_FILE")

## Validation Results

EOF
}

# Validate container security configuration
validate_container_security() {
    log "Validating container security configurations..."
    
    local report_file="$VALIDATION_OUTPUT_DIR/container-security.txt"
    
    {
        echo "=== Container Security Configuration Validation ==="
        echo ""
        
        # Check for security_opt configurations
        echo "## Security Options Check"
        if grep -q "no-new-privileges:true" "$COMPOSE_FILE"; then
            echo "✅ no-new-privileges enabled"
        else
            echo "❌ no-new-privileges not configured"
        fi
        
        if grep -q "apparmor:" "$COMPOSE_FILE"; then
            echo "✅ AppArmor profiles configured"
        else
            echo "⚠️  AppArmor profiles not configured"
        fi
        echo ""
        
        # Check for capability dropping
        echo "## Capability Management"
        if grep -q "cap_drop:" "$COMPOSE_FILE" && grep -q "ALL" "$COMPOSE_FILE"; then
            echo "✅ All capabilities dropped by default"
        else
            echo "❌ Capabilities not properly restricted"
        fi
        
        if grep -q "cap_add:" "$COMPOSE_FILE"; then
            echo "✅ Minimal capabilities added back"
            grep -A 5 "cap_add:" "$COMPOSE_FILE" | grep -E "^\s+-\s+" | sed 's/^/    /'
        else
            echo "⚠️  No capabilities explicitly added"
        fi
        echo ""
        
        # Check for read-only filesystem
        echo "## Filesystem Security"
        if grep -q "read_only: true" "$COMPOSE_FILE"; then
            echo "✅ Read-only filesystem enabled"
        else
            echo "⚠️  Read-only filesystem not configured"
        fi
        
        if grep -q "tmpfs:" "$COMPOSE_FILE"; then
            echo "✅ Temporary filesystems configured"
        else
            echo "⚠️  Temporary filesystems not configured"
        fi
        echo ""
        
        # Check for user configuration
        echo "## User Configuration"
        if grep -q "user:" "$COMPOSE_FILE"; then
            echo "✅ Non-root user configured"
            grep "user:" "$COMPOSE_FILE" | sed 's/^/    /'
        else
            echo "❌ Root user may be used (security risk)"
        fi
        echo ""
        
        # Check resource limits
        echo "## Resource Limits"
        if grep -q "deploy:" "$COMPOSE_FILE" && grep -q "limits:" "$COMPOSE_FILE"; then
            echo "✅ Resource limits configured"
        else
            echo "❌ Resource limits not configured"
        fi
        
        if grep -q "pids_limit:" "$COMPOSE_FILE"; then
            echo "✅ Process limits configured"
        else
            echo "⚠️  Process limits not configured"
        fi
        echo ""
        
    } > "$report_file"
    
    cat "$report_file"
}

# Validate network security
validate_network_security() {
    log "Validating network security configurations..."
    
    local report_file="$VALIDATION_OUTPUT_DIR/network-security.txt"
    
    {
        echo "=== Network Security Configuration Validation ==="
        echo ""
        
        # Check for network isolation
        echo "## Network Isolation"
        local network_count=$(grep -c "networks:" "$COMPOSE_FILE" || echo "0")
        if [[ "$network_count" -gt 1 ]]; then
            echo "✅ Multiple networks configured for isolation"
        else
            echo "⚠️  Single network - consider network segmentation"
        fi
        
        if grep -q "internal: true" "$COMPOSE_FILE"; then
            echo "✅ Internal networks configured"
        else
            echo "⚠️  No internal networks found"
        fi
        echo ""
        
        # Check port bindings
        echo "## Port Binding Security"
        if grep -q "127.0.0.1:" "$COMPOSE_FILE"; then
            echo "✅ Localhost-only port bindings found"
        else
            echo "⚠️  No localhost-only bindings found"
        fi
        
        if grep -q "ports:" "$COMPOSE_FILE"; then
            echo "📋 Port bindings:"
            grep -A 3 "ports:" "$COMPOSE_FILE" | grep -E "^\s+-\s+" | sed 's/^/    /'
        fi
        echo ""
        
        # Check for exposed ports vs published ports
        echo "## Port Exposure"
        if grep -q "expose:" "$COMPOSE_FILE"; then
            echo "✅ Internal port exposure configured"
        else
            echo "⚠️  No internal port exposure found"
        fi
        echo ""
        
        # Network driver options
        echo "## Network Driver Security"
        if grep -q "enable_icc.*false" "$COMPOSE_FILE"; then
            echo "✅ Inter-container communication restricted"
        else
            echo "⚠️  Inter-container communication not restricted"
        fi
        echo ""
        
    } > "$report_file"
    
    cat "$report_file"
}

# Validate volume security
validate_volume_security() {
    log "Validating volume security configurations..."
    
    local report_file="$VALIDATION_OUTPUT_DIR/volume-security.txt"
    
    {
        echo "=== Volume Security Configuration Validation ==="
        echo ""
        
        # Check for read-only volumes
        echo "## Volume Mount Security"
        if grep -q ":ro" "$COMPOSE_FILE"; then
            echo "✅ Read-only volume mounts found"
            grep ":ro" "$COMPOSE_FILE" | sed 's/^/    /'
        else
            echo "⚠️  No read-only volume mounts found"
        fi
        echo ""
        
        # Check for sensitive file mounts
        echo "## Sensitive File Handling"
        if grep -q "/keys:" "$COMPOSE_FILE"; then
            echo "📋 Key file mounts detected:"
            grep "/keys:" "$COMPOSE_FILE" | sed 's/^/    /'
            
            if grep "/keys:" "$COMPOSE_FILE" | grep -q ":ro"; then
                echo "✅ Key files mounted read-only"
            else
                echo "❌ Key files not mounted read-only"
            fi
        fi
        echo ""
        
        # Check for host path mounts
        echo "## Host Path Mount Security"
        local host_mounts=$(grep -E "^\s+-\s+/" "$COMPOSE_FILE" | wc -l)
        if [[ "$host_mounts" -gt 0 ]]; then
            echo "⚠️  Host path mounts detected ($host_mounts):"
            grep -E "^\s+-\s+/" "$COMPOSE_FILE" | sed 's/^/    /'
            echo "    Consider using named volumes for better security"
        else
            echo "✅ No direct host path mounts detected"
        fi
        echo ""
        
    } > "$report_file"
    
    cat "$report_file"
}

# Validate container runtime security
validate_runtime_security() {
    log "Validating container runtime security..."
    
    local report_file="$VALIDATION_OUTPUT_DIR/runtime-security.txt"
    
    {
        echo "=== Container Runtime Security Validation ==="
        echo ""
        
        # Check for privileged containers
        echo "## Privileged Container Check"
        if grep -q "privileged: true" "$COMPOSE_FILE"; then
            echo "❌ Privileged containers detected (security risk)"
        else
            echo "✅ No privileged containers detected"
        fi
        echo ""
        
        # Check for host network mode
        echo "## Network Mode Check"
        if grep -q "network_mode: host" "$COMPOSE_FILE"; then
            echo "❌ Host network mode detected (security risk)"
        else
            echo "✅ No host network mode detected"
        fi
        echo ""
        
        # Check for host PID mode
        echo "## PID Namespace Check"
        if grep -q "pid: host" "$COMPOSE_FILE"; then
            echo "❌ Host PID namespace detected (security risk)"
        else
            echo "✅ No host PID namespace detected"
        fi
        echo ""
        
        # Check for SYS_ADMIN capability
        echo "## Dangerous Capabilities Check"
        if grep -q "SYS_ADMIN" "$COMPOSE_FILE"; then
            echo "❌ SYS_ADMIN capability detected (high risk)"
        else
            echo "✅ No dangerous capabilities detected"
        fi
        echo ""
        
        # Check for device mounts
        echo "## Device Mount Check"
        if grep -q "devices:" "$COMPOSE_FILE"; then
            echo "⚠️  Device mounts detected:"
            grep -A 5 "devices:" "$COMPOSE_FILE" | grep -E "^\s+-\s+" | sed 's/^/    /'
        else
            echo "✅ No device mounts detected"
        fi
        echo ""
        
    } > "$report_file"
    
    cat "$report_file"
}

# Generate security score
calculate_security_score() {
    log "Calculating security score..."
    
    local score=0
    local max_score=100
    
    # Container security (40 points)
    grep -q "no-new-privileges:true" "$COMPOSE_FILE" && score=$((score + 10))
    grep -q "cap_drop:" "$COMPOSE_FILE" && grep -q "ALL" "$COMPOSE_FILE" && score=$((score + 10))
    grep -q "read_only: true" "$COMPOSE_FILE" && score=$((score + 10))
    grep -q "user:" "$COMPOSE_FILE" && score=$((score + 10))
    
    # Network security (30 points)
    grep -q "internal: true" "$COMPOSE_FILE" && score=$((score + 10))
    grep -q "127.0.0.1:" "$COMPOSE_FILE" && score=$((score + 10))
    [[ $(grep -c "networks:" "$COMPOSE_FILE" || echo "0") -gt 1 ]] && score=$((score + 10))
    
    # Volume security (20 points)
    grep -q ":ro" "$COMPOSE_FILE" && score=$((score + 10))
    ! grep -q "privileged: true" "$COMPOSE_FILE" && score=$((score + 10))
    
    # Runtime security (10 points)
    grep -q "pids_limit:" "$COMPOSE_FILE" && score=$((score + 5))
    grep -q "deploy:" "$COMPOSE_FILE" && score=$((score + 5))
    
    # Deduct points for security risks
    grep -q "privileged: true" "$COMPOSE_FILE" && score=$((score - 20))
    grep -q "network_mode: host" "$COMPOSE_FILE" && score=$((score - 15))
    grep -q "SYS_ADMIN" "$COMPOSE_FILE" && score=$((score - 15))
    
    local percentage=$((score * 100 / max_score))
    
    echo "=== Security Score ===" > "$VALIDATION_OUTPUT_DIR/security-score.txt"
    echo "Score: $score/$max_score ($percentage%)" >> "$VALIDATION_OUTPUT_DIR/security-score.txt"
    echo "" >> "$VALIDATION_OUTPUT_DIR/security-score.txt"
    
    if [[ $percentage -ge 90 ]]; then
        echo "✅ Excellent security configuration" >> "$VALIDATION_OUTPUT_DIR/security-score.txt"
    elif [[ $percentage -ge 80 ]]; then
        echo "✅ Good security configuration" >> "$VALIDATION_OUTPUT_DIR/security-score.txt"
    elif [[ $percentage -ge 70 ]]; then
        echo "⚠️  Adequate security configuration - improvements recommended" >> "$VALIDATION_OUTPUT_DIR/security-score.txt"
    else
        echo "❌ Poor security configuration - immediate improvements required" >> "$VALIDATION_OUTPUT_DIR/security-score.txt"
    fi
    
    cat "$VALIDATION_OUTPUT_DIR/security-score.txt"
}

# Generate comprehensive report
generate_comprehensive_report() {
    log "Generating comprehensive security validation report..."
    
    local report_file="$VALIDATION_OUTPUT_DIR/comprehensive-security-report.md"
    
    {
        echo "# Docker Security Validation Report"
        echo ""
        echo "**Generated:** $(date)"
        echo "**Compose File:** $(basename "$COMPOSE_FILE")"
        echo "**Validation Script:** $(basename "$0")"
        echo ""
        
        echo "## Security Score"
        echo ""
        echo '```'
        cat "$VALIDATION_OUTPUT_DIR/security-score.txt"
        echo '```'
        echo ""
        
        echo "## Container Security"
        echo ""
        echo '```'
        cat "$VALIDATION_OUTPUT_DIR/container-security.txt"
        echo '```'
        echo ""
        
        echo "## Network Security"
        echo ""
        echo '```'
        cat "$VALIDATION_OUTPUT_DIR/network-security.txt"
        echo '```'
        echo ""
        
        echo "## Volume Security"
        echo ""
        echo '```'
        cat "$VALIDATION_OUTPUT_DIR/volume-security.txt"
        echo '```'
        echo ""
        
        echo "## Runtime Security"
        echo ""
        echo '```'
        cat "$VALIDATION_OUTPUT_DIR/runtime-security.txt"
        echo '```'
        echo ""
        
        echo "## Recommendations"
        echo ""
        echo "### High Priority"
        echo "- Ensure all containers run as non-root users"
        echo "- Enable read-only filesystems with tmpfs for writable areas"
        echo "- Drop all capabilities and add only necessary ones"
        echo "- Use network segmentation with internal networks"
        echo ""
        echo "### Medium Priority"
        echo "- Implement resource limits for all containers"
        echo "- Use read-only volume mounts for configuration files"
        echo "- Enable process limits (pids_limit)"
        echo "- Configure proper logging with rotation"
        echo ""
        echo "### Low Priority"
        echo "- Add health checks to all services"
        echo "- Use specific image tags instead of 'latest'"
        echo "- Implement container image scanning in CI/CD"
        echo "- Add security monitoring and alerting"
        echo ""
        
        echo "## Security Checklist"
        echo ""
        echo "- [ ] All containers use non-root users"
        echo "- [ ] All capabilities dropped by default"
        echo "- [ ] Read-only filesystems enabled"
        echo "- [ ] Network segmentation implemented"
        echo "- [ ] Resource limits configured"
        echo "- [ ] Security options (no-new-privileges) enabled"
        echo "- [ ] Sensitive data mounted read-only"
        echo "- [ ] No privileged containers"
        echo "- [ ] No host network mode"
        echo "- [ ] Container image scanning implemented"
        echo ""
        
        echo "---"
        echo "*Report generated by Proxmox MCP Security Validator*"
    } > "$report_file"
    
    log "✅ Comprehensive report generated: $report_file"
}

# Main validation function
main() {
    log "🔍 Starting Docker security validation for $COMPOSE_FILE"
    echo "========================================================"
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    init_validation
    validate_container_security
    echo ""
    validate_network_security
    echo ""
    validate_volume_security
    echo ""
    validate_runtime_security
    echo ""
    calculate_security_score
    echo ""
    generate_comprehensive_report
    
    log "🎉 Security validation completed successfully!"
    echo ""
    echo "📋 Validation Results:"
    echo "======================"
    echo "   Reports Directory: $VALIDATION_OUTPUT_DIR"
    echo "   Comprehensive Report: $VALIDATION_OUTPUT_DIR/comprehensive-security-report.md"
    echo ""
}

# Handle script arguments
case "${1:-validate}" in
    "validate"|*.yml|*.yaml)
        main
        ;;
    *)
        echo "Usage: $0 [docker-compose-file.yml]"
        echo ""
        echo "Examples:"
        echo "  $0                              # Validate docker-compose.secure.yml"
        echo "  $0 docker-compose.prod.yml     # Validate specific file"
        exit 1
        ;;
esac