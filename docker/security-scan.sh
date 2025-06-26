#!/bin/bash
# Docker Security Scanning Script
# Performs security scans on Docker images and containers

set -euo pipefail

# Configuration
IMAGE_NAME="${1:-proxmox-mcp-server}"
IMAGE_TAG="${2:-latest}"
SCAN_OUTPUT_DIR="./security-reports"
TRIVY_DB_CACHE_DIR="/tmp/trivy-cache"

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
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if required tools are available
check_dependencies() {
    log "Checking security scanning dependencies..."
    
    local missing_tools=()
    
    # Check for Trivy (vulnerability scanner)
    if ! command -v trivy &> /dev/null; then
        missing_tools+=("trivy")
    fi
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    # Check for hadolint (Dockerfile linter)
    if ! command -v hadolint &> /dev/null; then
        warn "hadolint not found - Dockerfile linting will be skipped"
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
    fi
    
    log "✅ All required dependencies available"
}

# Install Trivy if not available
install_trivy() {
    if ! command -v trivy &> /dev/null; then
        log "Installing Trivy vulnerability scanner..."
        
        # Detect OS and architecture
        local os=$(uname -s | tr '[:upper:]' '[:lower:]')
        local arch=$(uname -m)
        
        case $arch in
            x86_64) arch="amd64" ;;
            arm64|aarch64) arch="arm64" ;;
            *) error "Unsupported architecture: $arch" ;;
        esac
        
        # Download and install Trivy
        local trivy_version="v0.47.0"
        local download_url="https://github.com/aquasecurity/trivy/releases/download/${trivy_version}/trivy_${trivy_version#v}_${os}_${arch}.tar.gz"
        
        curl -sSL "$download_url" | tar -xz -C /tmp
        sudo mv /tmp/trivy /usr/local/bin/
        chmod +x /usr/local/bin/trivy
        
        log "✅ Trivy installed successfully"
    fi
}

# Setup scan output directory
setup_output_dir() {
    mkdir -p "$SCAN_OUTPUT_DIR"
    log "Security reports will be saved to: $SCAN_OUTPUT_DIR"
}

# Dockerfile security linting
lint_dockerfile() {
    log "Performing Dockerfile security linting..."
    
    local dockerfile_path="../docker/Dockerfile.prod"
    local report_file="$SCAN_OUTPUT_DIR/hadolint-report.json"
    
    if command -v hadolint &> /dev/null && [[ -f "$dockerfile_path" ]]; then
        if hadolint --format json "$dockerfile_path" > "$report_file" 2>/dev/null; then
            log "✅ Dockerfile linting completed"
            
            # Check for critical issues
            local critical_count=$(jq -r '[.[] | select(.level == "error")] | length' "$report_file" 2>/dev/null || echo "0")
            if [[ "$critical_count" -gt 0 ]]; then
                warn "Found $critical_count critical Dockerfile issues"
                jq -r '.[] | select(.level == "error") | \"❌ \\(.rule): \\(.message)\"' "$report_file"
            fi
        else
            warn "Dockerfile linting failed"
        fi
    else
        warn "Skipping Dockerfile linting (hadolint not available or Dockerfile not found)"
    fi
}

# Image vulnerability scanning
scan_image_vulnerabilities() {
    log "Scanning image for vulnerabilities: $IMAGE_NAME:$IMAGE_TAG"
    
    local report_file="$SCAN_OUTPUT_DIR/trivy-vulnerabilities.json"
    local summary_file="$SCAN_OUTPUT_DIR/vulnerability-summary.txt"
    
    # Update Trivy database
    trivy image --download-db-only --cache-dir "$TRIVY_DB_CACHE_DIR"
    
    # Perform vulnerability scan
    if trivy image \
        --cache-dir "$TRIVY_DB_CACHE_DIR" \
        --format json \
        --output "$report_file" \
        --severity HIGH,CRITICAL \
        "$IMAGE_NAME:$IMAGE_TAG"; then
        
        # Generate summary
        {
            echo "=== Vulnerability Scan Summary ==="
            echo "Image: $IMAGE_NAME:$IMAGE_TAG"
            echo "Scan Date: $(date)"
            echo ""
            
            # Count vulnerabilities by severity
            local critical_count=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$report_file" 2>/dev/null || echo "0")
            local high_count=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$report_file" 2>/dev/null || echo "0")
            
            echo "Critical vulnerabilities: $critical_count"
            echo "High vulnerabilities: $high_count"
            echo ""
            
            if [[ "$critical_count" -gt 0 ]]; then
                echo "🚨 CRITICAL VULNERABILITIES FOUND:"
                jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL") | "- \(.VulnerabilityID): \(.Title) (Package: \(.PkgName))"' "$report_file" 2>/dev/null || true
                echo ""
            fi
            
            if [[ "$high_count" -gt 0 ]]; then
                echo "⚠️  HIGH SEVERITY VULNERABILITIES:"
                jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH") | "- \(.VulnerabilityID): \(.Title) (Package: \(.PkgName))"' "$report_file" 2>/dev/null | head -10 || true
                echo ""
            fi
        } > "$summary_file"
        
        log "✅ Vulnerability scan completed"
        cat "$summary_file"
        
        # Return non-zero exit code if critical vulnerabilities found
        if [[ "$critical_count" -gt 0 ]]; then
            error "Critical vulnerabilities found - build should not proceed to production"
        fi
    else
        error "Vulnerability scanning failed"
    fi
}

# Container configuration security scan
scan_container_config() {
    log "Scanning container configuration for security issues..."
    
    local report_file="$SCAN_OUTPUT_DIR/trivy-config.json"
    
    # Scan Docker Compose file for misconfigurations
    local compose_file="../docker/docker-compose.prod.yml"
    if [[ -f "$compose_file" ]]; then
        if trivy config \
            --cache-dir "$TRIVY_DB_CACHE_DIR" \
            --format json \
            --output "$report_file" \
            --severity HIGH,CRITICAL \
            "$compose_file"; then
            
            local issues_count=$(jq -r '[.Results[]?.Misconfigurations[]?] | length' "$report_file" 2>/dev/null || echo "0")
            
            if [[ "$issues_count" -gt 0 ]]; then
                warn "Found $issues_count configuration security issues"
                jq -r '.Results[]?.Misconfigurations[]? | "❌ \(.ID): \(.Title)"' "$report_file" 2>/dev/null || true
            else
                log "✅ No critical configuration issues found"
            fi
        else
            warn "Container configuration scan failed"
        fi
    else
        warn "Docker Compose file not found for configuration scanning"
    fi
}

# Generate security report
generate_security_report() {
    log "Generating comprehensive security report..."
    
    local report_file="$SCAN_OUTPUT_DIR/security-report.md"
    
    {
        echo "# Docker Security Scan Report"
        echo ""
        echo "**Image:** $IMAGE_NAME:$IMAGE_TAG"
        echo "**Scan Date:** $(date)"
        echo "**Generated by:** Docker Security Scanner"
        echo ""
        
        echo "## Summary"
        echo ""
        if [[ -f "$SCAN_OUTPUT_DIR/vulnerability-summary.txt" ]]; then
            cat "$SCAN_OUTPUT_DIR/vulnerability-summary.txt"
        fi
        echo ""
        
        echo "## Scan Results"
        echo ""
        echo "### Vulnerability Scan"
        if [[ -f "$SCAN_OUTPUT_DIR/trivy-vulnerabilities.json" ]]; then
            echo "- Detailed results: [trivy-vulnerabilities.json](./trivy-vulnerabilities.json)"
        fi
        echo ""
        
        echo "### Configuration Scan"
        if [[ -f "$SCAN_OUTPUT_DIR/trivy-config.json" ]]; then
            echo "- Detailed results: [trivy-config.json](./trivy-config.json)"
        fi
        echo ""
        
        echo "### Dockerfile Linting"
        if [[ -f "$SCAN_OUTPUT_DIR/hadolint-report.json" ]]; then
            echo "- Detailed results: [hadolint-report.json](./hadolint-report.json)"
        fi
        echo ""
        
        echo "## Recommendations"
        echo ""
        echo "1. **Critical Vulnerabilities**: Address all critical vulnerabilities before production deployment"
        echo "2. **High Severity Issues**: Plan to address high severity vulnerabilities in next update cycle"
        echo "3. **Configuration**: Review and fix any configuration security issues"
        echo "4. **Regular Scanning**: Implement automated security scanning in CI/CD pipeline"
        echo ""
        
        echo "---"
        echo "*Report generated by Proxmox MCP Security Scanner*"
    } > "$report_file"
    
    log "✅ Security report generated: $report_file"
}

# Main scanning function
main() {
    log "🔍 Starting Docker security scanning for $IMAGE_NAME:$IMAGE_TAG"
    echo "=================================================================="
    
    check_dependencies
    setup_output_dir
    lint_dockerfile
    scan_image_vulnerabilities
    scan_container_config
    generate_security_report
    
    log "🎉 Security scanning completed successfully!"
    echo ""
    echo "📋 Scan Results Summary:"
    echo "========================"
    echo "   Reports Directory: $SCAN_OUTPUT_DIR"
    echo "   Main Report: $SCAN_OUTPUT_DIR/security-report.md"
    echo ""
}

# Handle script arguments
case "${1:-scan}" in
    "scan")
        if [[ $# -ge 2 ]]; then
            main
        else
            echo "Usage: $0 scan <image_name> [image_tag]"
            echo "Example: $0 scan proxmox-mcp-server latest"
            exit 1
        fi
        ;;
    "install-tools")
        install_trivy
        ;;
    *)
        echo "Usage: $0 [scan|install-tools] <image_name> [image_tag]"
        echo ""
        echo "Commands:"
        echo "  scan          - Perform security scan on Docker image"
        echo "  install-tools - Install required security scanning tools"
        echo ""
        echo "Example:"
        echo "  $0 scan proxmox-mcp-server latest"
        exit 1
        ;;
esac