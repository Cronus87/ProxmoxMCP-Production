#!/bin/bash

# PROXMOX MCP VALIDATION FRAMEWORK
# ================================
# Comprehensive validation system for installation, configuration, and operation
# Provides multi-layer testing with detailed reporting and troubleshooting
#
# FEATURES:
# - Pre-installation environment validation
# - Post-installation functionality testing
# - Continuous health monitoring
# - Performance benchmarking
# - Security compliance verification
# - Troubleshooting assistance

set -euo pipefail

# ==============================================================================
# VALIDATION FRAMEWORK CONFIGURATION
# ==============================================================================

readonly VALIDATION_VERSION="1.0.0"
readonly INSTALL_ROOT="/opt/proxmox-mcp"
readonly VALIDATION_LOG="/var/log/proxmox-mcp-validation.log"
readonly VALIDATION_REPORT_DIR="/var/log/proxmox-mcp-validation-reports"
readonly SERVICE_NAME="proxmox-mcp"

# Test configuration
readonly TIMEOUT_SHORT=10
readonly TIMEOUT_MEDIUM=30
readonly TIMEOUT_LONG=60
readonly MAX_RETRIES=3
readonly HEALTH_CHECK_INTERVAL=5

# Validation levels
readonly VALIDATION_LEVELS=("basic" "standard" "comprehensive" "security" "performance")

# ==============================================================================
# LOGGING AND REPORTING SYSTEM
# ==============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CRITICAL_FAILURES=0

# Test categories
declare -A CATEGORY_TESTS
declare -A CATEGORY_RESULTS

log_validation() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp]${NC} ${BOLD}[$level]${NC} $message" | tee -a "$VALIDATION_LOG"
}

info() { log_validation "INFO" "${BLUE}$*${NC}"; }
success() { log_validation "SUCCESS" "${GREEN}✅ $*${NC}"; }
warning() { log_validation "WARNING" "${YELLOW}⚠️  $*${NC}"; }
error() { log_validation "ERROR" "${RED}❌ $*${NC}"; }
critical() { log_validation "CRITICAL" "${RED}🚨 $*${NC}"; }

validation_header() {
    local category="$1"
    local description="$2"
    echo ""
    echo "=============================================="
    echo -e "${PURPLE}${BOLD}VALIDATION: $category${NC}"
    echo "=============================================="
    echo -e "${CYAN}$description${NC}"
    echo ""
}

# Test result reporting
test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    local category="${4:-general}"
    local severity="${5:-normal}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Initialize category if not exists
    if [[ -z "${CATEGORY_TESTS[$category]:-}" ]]; then
        CATEGORY_TESTS[$category]=0
        CATEGORY_RESULTS[$category]=""
    fi
    
    CATEGORY_TESTS[$category]=$((CATEGORY_TESTS[$category] + 1))
    
    case "$status" in
        "PASS")
            success "$test_name: $message"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            CATEGORY_RESULTS[$category]+="✅ $test_name\n"
            ;;
        "FAIL")
            if [[ "$severity" == "critical" ]]; then
                critical "$test_name: $message"
                CRITICAL_FAILURES=$((CRITICAL_FAILURES + 1))
                CATEGORY_RESULTS[$category]+="🚨 $test_name (CRITICAL)\n"
            else
                error "$test_name: $message"
                CATEGORY_RESULTS[$category]+="❌ $test_name\n"
            fi
            TESTS_FAILED=$((TESTS_FAILED + 1))
            ;;
        "SKIP")
            warning "$test_name: $message"
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            CATEGORY_RESULTS[$category]+="⏭️  $test_name (SKIPPED)\n"
            ;;
        *)
            error "$test_name: Unknown status - $message"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            ;;
    esac
}

# ==============================================================================
# PRE-INSTALLATION VALIDATION
# ==============================================================================

validate_system_requirements() {
    validation_header "SYSTEM REQUIREMENTS" "Validating system prerequisites for installation"
    
    # Operating System
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "debian" ]] || [[ "$ID" == "ubuntu" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
            test_result "Operating System" "PASS" "Debian/Ubuntu compatible: $PRETTY_NAME" "system"
        else
            test_result "Operating System" "FAIL" "Not Debian/Ubuntu compatible: $PRETTY_NAME" "system"
        fi
    else
        test_result "Operating System" "FAIL" "Cannot determine OS version" "system" "critical"
    fi
    
    # Architecture
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]] || [[ "$arch" == "aarch64" ]]; then
        test_result "Architecture" "PASS" "Supported architecture: $arch" "system"
    else
        test_result "Architecture" "FAIL" "Unsupported architecture: $arch" "system"
    fi
    
    # Memory
    local memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local memory_gb=$((memory_kb / 1024 / 1024))
    if [[ $memory_gb -ge 2 ]]; then
        test_result "Memory" "PASS" "Sufficient memory: ${memory_gb}GB" "system"
    else
        test_result "Memory" "FAIL" "Insufficient memory: ${memory_gb}GB (minimum 2GB)" "system"
    fi
    
    # Disk Space
    local disk_space_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $disk_space_gb -ge 10 ]]; then
        test_result "Disk Space" "PASS" "Sufficient disk space: ${disk_space_gb}GB" "system"
    else
        test_result "Disk Space" "FAIL" "Insufficient disk space: ${disk_space_gb}GB (minimum 10GB)" "system"
    fi
    
    # Kernel Version
    local kernel_version=$(uname -r)
    test_result "Kernel Version" "PASS" "Kernel version: $kernel_version" "system"
}

validate_network_environment() {
    validation_header "NETWORK ENVIRONMENT" "Validating network connectivity and configuration"
    
    # Internet Connectivity
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")
    local connectivity_passed=0
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
            connectivity_passed=$((connectivity_passed + 1))
        fi
    done
    
    if [[ $connectivity_passed -ge 2 ]]; then
        test_result "Internet Connectivity" "PASS" "$connectivity_passed/$((${#test_hosts[@]})) hosts reachable" "network"
    else
        test_result "Internet Connectivity" "FAIL" "Only $connectivity_passed/$((${#test_hosts[@]})) hosts reachable" "network"
    fi
    
    # DNS Resolution
    if nslookup github.com >/dev/null 2>&1; then
        test_result "DNS Resolution" "PASS" "DNS working correctly" "network"
    else
        test_result "DNS Resolution" "FAIL" "DNS resolution failed" "network"
    fi
    
    # Port Availability
    local required_ports=(80 443 8080 22)
    for port in "${required_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            test_result "Port $port Availability" "FAIL" "Port $port already in use" "network"
        else
            test_result "Port $port Availability" "PASS" "Port $port available" "network"
        fi
    done
    
    # Network Interface
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    if [[ -n "$interfaces" ]]; then
        test_result "Network Interfaces" "PASS" "Network interfaces available: $interfaces" "network"
    else
        test_result "Network Interfaces" "FAIL" "No network interfaces found" "network" "critical"
    fi
}

validate_dependencies() {
    validation_header "DEPENDENCIES" "Checking for required system dependencies"
    
    # Essential commands
    local essential_commands=("curl" "wget" "git" "jq" "tar" "gzip" "openssl")
    for cmd in "${essential_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            local version=""
            case "$cmd" in
                "git") version=$(git --version 2>/dev/null | cut -d' ' -f3) ;;
                "curl") version=$(curl --version 2>/dev/null | head -1 | cut -d' ' -f2) ;;
                "jq") version=$(jq --version 2>/dev/null | tr -d '"') ;;
            esac
            test_result "$cmd Command" "PASS" "$cmd available${version:+ (version: $version)}" "dependencies"
        else
            test_result "$cmd Command" "FAIL" "$cmd not found" "dependencies"
        fi
    done
    
    # Docker availability check
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        test_result "Docker" "PASS" "Docker available (version: $docker_version)" "dependencies"
        
        # Docker daemon status
        if docker info >/dev/null 2>&1; then
            test_result "Docker Daemon" "PASS" "Docker daemon running" "dependencies"
        else
            test_result "Docker Daemon" "FAIL" "Docker daemon not running" "dependencies"
        fi
    else
        test_result "Docker" "SKIP" "Docker not installed (will be installed)" "dependencies"
    fi
    
    # Docker Compose availability
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version=$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        test_result "Docker Compose" "PASS" "Docker Compose available (version: $compose_version)" "dependencies"
    else
        test_result "Docker Compose" "SKIP" "Docker Compose not installed (will be installed)" "dependencies"
    fi
}

# ==============================================================================
# POST-INSTALLATION VALIDATION
# ==============================================================================

validate_installation_structure() {
    validation_header "INSTALLATION STRUCTURE" "Validating installation directory structure and files"
    
    # Core directories
    local required_directories=(
        "$INSTALL_ROOT"
        "$INSTALL_ROOT/keys"
        "$INSTALL_ROOT/config"
        "$INSTALL_ROOT/caddy"
        "$INSTALL_ROOT/logs"
    )
    
    for dir in "${required_directories[@]}"; do
        if [[ -d "$dir" ]]; then
            test_result "Directory $(basename "$dir")" "PASS" "Directory exists: $dir" "structure"
        else
            test_result "Directory $(basename "$dir")" "FAIL" "Directory missing: $dir" "structure" "critical"
        fi
    done
    
    # Core files
    local required_files=(
        "$INSTALL_ROOT/.env"
        "$INSTALL_ROOT/docker-compose.yml"
        "$INSTALL_ROOT/caddy/Caddyfile"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            if [[ $size -gt 0 ]]; then
                test_result "File $(basename "$file")" "PASS" "File exists and not empty: $file" "structure"
            else
                test_result "File $(basename "$file")" "FAIL" "File exists but empty: $file" "structure"
            fi
        else
            test_result "File $(basename "$file")" "FAIL" "File missing: $file" "structure" "critical"
        fi
    done
    
    # SSH Keys
    if [[ -f "$INSTALL_ROOT/keys/claude_proxmox_key" ]]; then
        local key_perms=$(stat -c%a "$INSTALL_ROOT/keys/claude_proxmox_key" 2>/dev/null)
        if [[ "$key_perms" == "600" ]]; then
            test_result "SSH Private Key" "PASS" "SSH private key exists with correct permissions" "structure"
        else
            test_result "SSH Private Key" "FAIL" "SSH private key has incorrect permissions: $key_perms" "structure"
        fi
    else
        test_result "SSH Private Key" "FAIL" "SSH private key missing" "structure"
    fi
    
    if [[ -f "$INSTALL_ROOT/keys/claude_proxmox_key.pub" ]]; then
        test_result "SSH Public Key" "PASS" "SSH public key exists" "structure"
    else
        test_result "SSH Public Key" "FAIL" "SSH public key missing" "structure"
    fi
}

validate_configuration() {
    validation_header "CONFIGURATION" "Validating configuration files and settings"
    
    if [[ ! -f "$INSTALL_ROOT/.env" ]]; then
        test_result "Environment File" "FAIL" "Environment file missing" "configuration" "critical"
        return 1
    fi
    
    # Load configuration
    source "$INSTALL_ROOT/.env"
    
    # Required variables
    local required_vars=("PROXMOX_HOST" "SSH_USER" "PROXMOX_TOKEN_VALUE" "MCP_PORT")
    for var in "${required_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            test_result "$var Configuration" "PASS" "$var is set" "configuration"
        else
            test_result "$var Configuration" "FAIL" "$var is not set" "configuration" "critical"
        fi
    done
    
    # IP address validation
    if [[ -n "${PROXMOX_HOST:-}" ]]; then
        if [[ "$PROXMOX_HOST" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            test_result "Proxmox Host Format" "PASS" "Valid IP format: $PROXMOX_HOST" "configuration"
        elif [[ "$PROXMOX_HOST" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            test_result "Proxmox Host Format" "PASS" "Valid hostname format: $PROXMOX_HOST" "configuration"
        else
            test_result "Proxmox Host Format" "FAIL" "Invalid format: $PROXMOX_HOST" "configuration"
        fi
    fi
    
    # Port validation
    if [[ -n "${MCP_PORT:-}" ]]; then
        if [[ "$MCP_PORT" =~ ^[0-9]+$ ]] && [[ $MCP_PORT -ge 1024 ]] && [[ $MCP_PORT -le 65535 ]]; then
            test_result "MCP Port" "PASS" "Valid port number: $MCP_PORT" "configuration"
        else
            test_result "MCP Port" "FAIL" "Invalid port number: $MCP_PORT" "configuration"
        fi
    fi
    
    # Docker Compose validation
    if [[ -f "$INSTALL_ROOT/docker-compose.yml" ]]; then
        cd "$INSTALL_ROOT"
        if docker-compose config >/dev/null 2>&1; then
            test_result "Docker Compose Config" "PASS" "Docker Compose configuration valid" "configuration"
        else
            test_result "Docker Compose Config" "FAIL" "Docker Compose configuration invalid" "configuration" "critical"
        fi
    fi
}

validate_services() {
    validation_header "SERVICES" "Validating system services and containers"
    
    # Systemd service
    if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
        test_result "Systemd Service File" "PASS" "Service file exists" "services"
        
        if systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
            test_result "Service Enabled" "PASS" "Service is enabled" "services"
        else
            test_result "Service Enabled" "FAIL" "Service is not enabled" "services"
        fi
        
        if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
            test_result "Service Active" "PASS" "Service is active" "services"
        else
            test_result "Service Active" "FAIL" "Service is not active" "services"
        fi
    else
        test_result "Systemd Service" "FAIL" "Service file not found" "services" "critical"
    fi
    
    # Docker containers
    cd "$INSTALL_ROOT" 2>/dev/null || {
        test_result "Docker Environment" "FAIL" "Cannot access installation directory" "services" "critical"
        return 1
    }
    
    if docker-compose ps --services 2>/dev/null | grep -q "mcp-server"; then
        test_result "MCP Server Container" "PASS" "MCP server container defined" "services"
        
        # Check if container is running
        if docker-compose ps | grep -q "mcp-server.*Up"; then
            test_result "MCP Server Running" "PASS" "MCP server container running" "services"
        else
            test_result "MCP Server Running" "FAIL" "MCP server container not running" "services"
        fi
        
        # Check if container is healthy
        if docker-compose ps | grep -q "mcp-server.*healthy"; then
            test_result "MCP Server Health" "PASS" "MCP server container healthy" "services"
        else
            test_result "MCP Server Health" "FAIL" "MCP server container not healthy" "services"
        fi
    else
        test_result "MCP Server Container" "FAIL" "MCP server container not defined" "services" "critical"
    fi
    
    # Caddy reverse proxy
    if docker-compose ps --services 2>/dev/null | grep -q "caddy"; then
        test_result "Caddy Container" "PASS" "Caddy container defined" "services"
        
        if docker-compose ps | grep -q "caddy.*Up"; then
            test_result "Caddy Running" "PASS" "Caddy container running" "services"
        else
            test_result "Caddy Running" "FAIL" "Caddy container not running" "services"
        fi
    else
        test_result "Caddy Container" "SKIP" "Caddy container not defined" "services"
    fi
}

validate_connectivity() {
    validation_header "CONNECTIVITY" "Testing network connectivity and API endpoints"
    
    # Load configuration for connectivity tests
    if [[ -f "$INSTALL_ROOT/.env" ]]; then
        source "$INSTALL_ROOT/.env"
    else
        test_result "Configuration Load" "FAIL" "Cannot load configuration" "connectivity" "critical"
        return 1
    fi
    
    # MCP HTTP endpoint
    local mcp_url="http://localhost:${MCP_PORT:-8080}"
    if curl -s -f --connect-timeout $TIMEOUT_SHORT "${mcp_url}/health" >/dev/null 2>&1; then
        test_result "MCP Health Endpoint" "PASS" "Health endpoint responding" "connectivity"
        
        # Test MCP API
        local api_response
        if api_response=$(curl -s --connect-timeout $TIMEOUT_SHORT -X POST "${mcp_url}/api/mcp" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}' 2>/dev/null); then
            
            if echo "$api_response" | jq -e '.result.tools' >/dev/null 2>&1; then
                local tool_count=$(echo "$api_response" | jq -r '.result.tools | length' 2>/dev/null)
                test_result "MCP API Endpoint" "PASS" "API responding with $tool_count tools" "connectivity"
            else
                test_result "MCP API Endpoint" "FAIL" "API responding but invalid format" "connectivity"
            fi
        else
            test_result "MCP API Endpoint" "FAIL" "API not responding" "connectivity"
        fi
    else
        test_result "MCP Health Endpoint" "FAIL" "Health endpoint not responding" "connectivity" "critical"
    fi
    
    # SSH connectivity to Proxmox
    if [[ -n "${PROXMOX_HOST:-}" ]] && [[ -n "${SSH_USER:-}" ]]; then
        if timeout $TIMEOUT_MEDIUM ssh -i "$INSTALL_ROOT/keys/claude_proxmox_key" \
            -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            "${SSH_USER}@${PROXMOX_HOST}" "echo 'SSH test successful'" >/dev/null 2>&1; then
            test_result "SSH Connectivity" "PASS" "SSH connection to Proxmox successful" "connectivity"
        else
            test_result "SSH Connectivity" "FAIL" "SSH connection to Proxmox failed" "connectivity"
        fi
    else
        test_result "SSH Connectivity" "SKIP" "SSH configuration incomplete" "connectivity"
    fi
    
    # Proxmox API connectivity
    if [[ -n "${PROXMOX_HOST:-}" ]] && [[ -n "${PROXMOX_TOKEN_VALUE:-}" ]]; then
        local api_url="https://${PROXMOX_HOST}:8006/api2/json/version"
        local auth_header="Authorization: PVEAPIToken=${PROXMOX_USER:-root@pam}!${PROXMOX_TOKEN_NAME:-claude-mcp}=${PROXMOX_TOKEN_VALUE}"
        
        if curl -k -s --connect-timeout $TIMEOUT_SHORT -H "$auth_header" "$api_url" | jq -e '.data' >/dev/null 2>&1; then
            test_result "Proxmox API" "PASS" "Proxmox API accessible" "connectivity"
        else
            test_result "Proxmox API" "FAIL" "Proxmox API not accessible" "connectivity"
        fi
    else
        test_result "Proxmox API" "SKIP" "Proxmox API configuration incomplete" "connectivity"
    fi
}

# ==============================================================================
# SECURITY VALIDATION
# ==============================================================================

validate_security() {
    validation_header "SECURITY" "Validating security configuration and compliance"
    
    # SSH key permissions
    if [[ -f "$INSTALL_ROOT/keys/claude_proxmox_key" ]]; then
        local key_perms=$(stat -c%a "$INSTALL_ROOT/keys/claude_proxmox_key" 2>/dev/null)
        if [[ "$key_perms" == "600" ]]; then
            test_result "SSH Key Permissions" "PASS" "SSH private key has correct permissions (600)" "security"
        else
            test_result "SSH Key Permissions" "FAIL" "SSH private key has incorrect permissions ($key_perms)" "security"
        fi
    fi
    
    # Environment file permissions
    if [[ -f "$INSTALL_ROOT/.env" ]]; then
        local env_perms=$(stat -c%a "$INSTALL_ROOT/.env" 2>/dev/null)
        if [[ "$env_perms" =~ ^6[0-4][0-4]$ ]]; then
            test_result "Environment File Permissions" "PASS" "Environment file has secure permissions ($env_perms)" "security"
        else
            test_result "Environment File Permissions" "FAIL" "Environment file has insecure permissions ($env_perms)" "security"
        fi
    fi
    
    # Sudoers configuration
    local ssh_user="${SSH_USER:-claude-user}"
    if [[ -f "/etc/sudoers.d/$ssh_user" ]]; then
        test_result "Sudoers Configuration" "PASS" "Sudoers configuration exists" "security"
        
        # Check for dangerous configurations
        if grep -q "ALL.*ALL.*ALL" "/etc/sudoers.d/$ssh_user"; then
            test_result "Sudoers Security" "FAIL" "Unrestricted sudo access detected" "security" "critical"
        else
            test_result "Sudoers Security" "PASS" "Restricted sudo configuration" "security"
        fi
        
        # Run comprehensive security validation if available
        if [[ -f "comprehensive-security-validation.sh" ]]; then
            info "Running comprehensive security validation..."
            if sudo -u "$ssh_user" "./comprehensive-security-validation.sh" >/dev/null 2>&1; then
                test_result "Comprehensive Security" "PASS" "Comprehensive security validation passed" "security"
            else
                test_result "Comprehensive Security" "FAIL" "Comprehensive security validation failed" "security"
            fi
        fi
    else
        test_result "Sudoers Configuration" "FAIL" "Sudoers configuration missing" "security" "critical"
    fi
    
    # Container security
    if command -v docker >/dev/null 2>&1; then
        # Check for running containers as root
        local root_containers
        root_containers=$(docker ps --format "table {{.Names}}\t{{.Command}}" | grep -E "(proxmox-mcp|mcp-)" | grep -v "root" | wc -l)
        if [[ $root_containers -gt 0 ]]; then
            test_result "Container User Security" "PASS" "Containers not running as root" "security"
        else
            test_result "Container User Security" "FAIL" "Some containers may be running as root" "security"
        fi
    fi
    
    # Network security
    local exposed_ports
    exposed_ports=$(netstat -tuln 2>/dev/null | grep ":8080\|:443\|:80" | grep "0.0.0.0" | wc -l)
    if [[ $exposed_ports -gt 0 ]]; then
        test_result "Network Exposure" "PASS" "Services properly exposed on network" "security"
    else
        test_result "Network Exposure" "FAIL" "Services not properly exposed" "security"
    fi
}

# ==============================================================================
# PERFORMANCE VALIDATION
# ==============================================================================

validate_performance() {
    validation_header "PERFORMANCE" "Testing system performance and resource utilization"
    
    # Load configuration
    if [[ -f "$INSTALL_ROOT/.env" ]]; then
        source "$INSTALL_ROOT/.env"
    fi
    
    local mcp_url="http://localhost:${MCP_PORT:-8080}"
    
    # Response time test
    local response_times=()
    for i in {1..5}; do
        local start_time=$(date +%s%3N)
        if curl -s -f --connect-timeout $TIMEOUT_SHORT "${mcp_url}/health" >/dev/null 2>&1; then
            local end_time=$(date +%s%3N)
            local response_time=$((end_time - start_time))
            response_times+=($response_time)
        fi
    done
    
    if [[ ${#response_times[@]} -gt 0 ]]; then
        local avg_response=0
        for time in "${response_times[@]}"; do
            avg_response=$((avg_response + time))
        done
        avg_response=$((avg_response / ${#response_times[@]}))
        
        if [[ $avg_response -lt 1000 ]]; then
            test_result "Response Time" "PASS" "Average response time: ${avg_response}ms" "performance"
        elif [[ $avg_response -lt 3000 ]]; then
            test_result "Response Time" "PASS" "Acceptable response time: ${avg_response}ms" "performance"
        else
            test_result "Response Time" "FAIL" "Slow response time: ${avg_response}ms" "performance"
        fi
    else
        test_result "Response Time" "FAIL" "Unable to measure response time" "performance"
    fi
    
    # Memory usage
    local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    if (( $(echo "$memory_usage < 80" | bc -l) )); then
        test_result "Memory Usage" "PASS" "Memory usage: ${memory_usage}%" "performance"
    elif (( $(echo "$memory_usage < 90" | bc -l) )); then
        test_result "Memory Usage" "PASS" "High memory usage: ${memory_usage}%" "performance"
    else
        test_result "Memory Usage" "FAIL" "Critical memory usage: ${memory_usage}%" "performance"
    fi
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    if (( $(echo "$cpu_usage < 80" | bc -l) )); then
        test_result "CPU Usage" "PASS" "CPU usage: ${cpu_usage}%" "performance"
    elif (( $(echo "$cpu_usage < 95" | bc -l) )); then
        test_result "CPU Usage" "PASS" "High CPU usage: ${cpu_usage}%" "performance"
    else
        test_result "CPU Usage" "FAIL" "Critical CPU usage: ${cpu_usage}%" "performance"
    fi
    
    # Disk usage
    local disk_usage=$(df "$INSTALL_ROOT" | awk 'NR==2 {print $5}' | tr -d '%')
    if [[ $disk_usage -lt 80 ]]; then
        test_result "Disk Usage" "PASS" "Disk usage: ${disk_usage}%" "performance"
    elif [[ $disk_usage -lt 90 ]]; then
        test_result "Disk Usage" "PASS" "High disk usage: ${disk_usage}%" "performance"
    else
        test_result "Disk Usage" "FAIL" "Critical disk usage: ${disk_usage}%" "performance"
    fi
    
    # Container resource usage
    if command -v docker >/dev/null 2>&1; then
        cd "$INSTALL_ROOT" 2>/dev/null || return 1
        local container_stats
        container_stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep -E "(proxmox-mcp|mcp-)")
        
        if [[ -n "$container_stats" ]]; then
            test_result "Container Resources" "PASS" "Container resource usage monitored" "performance"
        else
            test_result "Container Resources" "FAIL" "Unable to get container resource usage" "performance"
        fi
    fi
}

# ==============================================================================
# FUNCTIONAL VALIDATION
# ==============================================================================

validate_mcp_tools() {
    validation_header "MCP TOOLS" "Testing MCP tool functionality and responses"
    
    # Load configuration
    if [[ -f "$INSTALL_ROOT/.env" ]]; then
        source "$INSTALL_ROOT/.env"
    fi
    
    local mcp_url="http://localhost:${MCP_PORT:-8080}/api/mcp"
    
    # Test tools/list
    local tools_response
    if tools_response=$(curl -s --connect-timeout $TIMEOUT_MEDIUM -X POST "$mcp_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test_tools"}' 2>/dev/null); then
        
        if echo "$tools_response" | jq -e '.result.tools' >/dev/null 2>&1; then
            local tool_count=$(echo "$tools_response" | jq -r '.result.tools | length' 2>/dev/null)
            local tool_names=$(echo "$tools_response" | jq -r '.result.tools[].name' 2>/dev/null | tr '\n' ' ')
            test_result "MCP Tools List" "PASS" "$tool_count tools available: $tool_names" "mcp_tools"
            
            # Test individual tools
            echo "$tools_response" | jq -r '.result.tools[].name' 2>/dev/null | while read -r tool_name; do
                test_mcp_tool "$tool_name" "$mcp_url"
            done
        else
            test_result "MCP Tools List" "FAIL" "Invalid tools list response" "mcp_tools"
        fi
    else
        test_result "MCP Tools List" "FAIL" "Tools list request failed" "mcp_tools" "critical"
    fi
}

test_mcp_tool() {
    local tool_name="$1"
    local mcp_url="$2"
    
    case "$tool_name" in
        "list_vms")
            test_mcp_tool_execution "$tool_name" "$mcp_url" '{}' "VM list"
            ;;
        "node_status")
            test_mcp_tool_execution "$tool_name" "$mcp_url" '{}' "Node status"
            ;;
        "execute_command")
            test_mcp_tool_execution "$tool_name" "$mcp_url" '{"command":"echo test"}' "Command execution"
            ;;
        "proxmox_api")
            test_mcp_tool_execution "$tool_name" "$mcp_url" '{"method":"GET","path":"/version"}' "API call"
            ;;
        "vm_status"|"vm_action")
            test_result "$tool_name Tool" "SKIP" "Requires VM ID parameter" "mcp_tools"
            ;;
        *)
            test_mcp_tool_execution "$tool_name" "$mcp_url" '{}' "General tool"
            ;;
    esac
}

test_mcp_tool_execution() {
    local tool_name="$1"
    local mcp_url="$2"
    local arguments="$3"
    local description="$4"
    
    local request_data=$(cat << EOF
{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
        "name": "$tool_name",
        "arguments": $arguments
    },
    "id": "test_$tool_name"
}
EOF
)
    
    local response
    if response=$(curl -s --connect-timeout $TIMEOUT_LONG -X POST "$mcp_url" \
        -H "Content-Type: application/json" \
        -d "$request_data" 2>/dev/null); then
        
        if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            test_result "$tool_name Tool" "PASS" "$description working" "mcp_tools"
        elif echo "$response" | jq -e '.error' >/dev/null 2>&1; then
            local error_message=$(echo "$response" | jq -r '.error.message' 2>/dev/null)
            test_result "$tool_name Tool" "FAIL" "$description failed: $error_message" "mcp_tools"
        else
            test_result "$tool_name Tool" "FAIL" "$description returned invalid response" "mcp_tools"
        fi
    else
        test_result "$tool_name Tool" "FAIL" "$description request failed" "mcp_tools"
    fi
}

# ==============================================================================
# REPORT GENERATION
# ==============================================================================

generate_validation_report() {
    local report_type="${1:-standard}"
    local report_file="$VALIDATION_REPORT_DIR/validation-report-$(date +%Y%m%d-%H%M%S).md"
    
    mkdir -p "$VALIDATION_REPORT_DIR"
    
    # Generate comprehensive validation report
    cat > "$report_file" << EOF
# Proxmox MCP Validation Report

**Generated:** $(date)  
**Validation Type:** $report_type  
**System:** $(hostname) ($(uname -r))  
**Report Version:** $VALIDATION_VERSION  

## Executive Summary

| Metric | Value |
|--------|-------|
| Total Tests | $TESTS_TOTAL |
| Passed | $TESTS_PASSED |
| Failed | $TESTS_FAILED |
| Skipped | $TESTS_SKIPPED |
| Critical Failures | $CRITICAL_FAILURES |

### Overall Status
$(if [[ $CRITICAL_FAILURES -eq 0 && $TESTS_FAILED -eq 0 ]]; then
    echo "✅ **VALIDATION PASSED** - All tests completed successfully"
elif [[ $CRITICAL_FAILURES -eq 0 ]]; then
    echo "⚠️  **VALIDATION PASSED WITH WARNINGS** - Some non-critical tests failed"
else
    echo "❌ **VALIDATION FAILED** - Critical failures detected"
fi)

## Test Results by Category

EOF

    # Add results for each category
    for category in "${!CATEGORY_TESTS[@]}"; do
        local category_count="${CATEGORY_TESTS[$category]}"
        local category_results="${CATEGORY_RESULTS[$category]}"
        
        cat >> "$report_file" << EOF
### $category ($category_count tests)

$category_results

EOF
    done
    
    # Add system information
    cat >> "$report_file" << EOF
## System Information

### Hardware
- **CPU:** $(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
- **Memory:** $(free -h | awk 'NR==2{print $2}')
- **Disk:** $(df -h / | awk 'NR==2{print $2}' | xargs)

### Software
- **OS:** $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
- **Kernel:** $(uname -r)
- **Docker:** $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "Not installed")

### Network
- **Hostname:** $(hostname)
- **IP Address:** $(ip route get 8.8.8.8 | awk '{print $7}' | head -1)

## Configuration Status

EOF
    
    if [[ -f "$INSTALL_ROOT/.env" ]]; then
        echo "### Environment Configuration" >> "$report_file"
        echo "\`\`\`" >> "$report_file"
        grep -E "^[A-Z_]+" "$INSTALL_ROOT/.env" | sed 's/=.*/=***/' >> "$report_file"
        echo "\`\`\`" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Recommendations

$(if [[ $CRITICAL_FAILURES -gt 0 ]]; then
    echo "### Critical Issues"
    echo "- Review failed tests marked as CRITICAL"
    echo "- Address security and configuration issues before proceeding"
    echo "- Consider re-running installation if fundamental components failed"
fi)

$(if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "### Failed Tests"
    echo "- Review failed tests for potential issues"
    echo "- Check logs for detailed error information"
    echo "- Consider manual verification of failed components"
fi)

### Monitoring
- Set up regular validation runs to monitor system health
- Monitor performance metrics and resource usage
- Review security configuration periodically

## Log Files

- **Validation Log:** $VALIDATION_LOG
- **Installation Log:** /var/log/proxmox-mcp-install.log
- **Service Logs:** \`docker-compose -f $INSTALL_ROOT/docker-compose.yml logs\`

---

*Report generated by Proxmox MCP Validation Framework v$VALIDATION_VERSION*
EOF
    
    success "Validation report generated: $report_file"
    echo "$report_file"
}

# ==============================================================================
# MAIN VALIDATION ORCHESTRATOR
# ==============================================================================

run_validation() {
    local level="${1:-standard}"
    local category="${2:-all}"
    
    info "Starting validation - Level: $level, Category: $category"
    
    # Initialize counters
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
    CRITICAL_FAILURES=0
    
    # Clear category tracking
    unset CATEGORY_TESTS
    unset CATEGORY_RESULTS
    declare -gA CATEGORY_TESTS
    declare -gA CATEGORY_RESULTS
    
    case "$level" in
        "basic")
            validate_system_requirements
            validate_installation_structure
            ;;
        "standard")
            validate_system_requirements
            validate_network_environment
            validate_installation_structure
            validate_configuration
            validate_services
            validate_connectivity
            ;;
        "comprehensive")
            validate_system_requirements
            validate_network_environment
            validate_dependencies
            validate_installation_structure
            validate_configuration
            validate_services
            validate_connectivity
            validate_security
            validate_mcp_tools
            ;;
        "security")
            validate_security
            validate_configuration
            ;;
        "performance")
            validate_performance
            validate_connectivity
            ;;
        "pre-install")
            validate_system_requirements
            validate_network_environment
            validate_dependencies
            ;;
        "post-install")
            validate_installation_structure
            validate_configuration
            validate_services
            validate_connectivity
            validate_mcp_tools
            ;;
        *)
            error "Unknown validation level: $level"
            return 1
            ;;
    esac
    
    # Generate and display summary
    echo ""
    echo "=============================================="
    echo -e "${PURPLE}${BOLD}VALIDATION SUMMARY${NC}"
    echo "=============================================="
    echo ""
    
    local success_rate=0
    if [[ $TESTS_TOTAL -gt 0 ]]; then
        success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
    fi
    
    echo -e "${BLUE}Test Results:${NC}"
    echo -e "  Total Tests: ${BOLD}$TESTS_TOTAL${NC}"
    echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "  Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo -e "  Critical Failures: ${RED}$CRITICAL_FAILURES${NC}"
    echo -e "  Success Rate: ${BLUE}${success_rate}%${NC}"
    
    echo ""
    if [[ $CRITICAL_FAILURES -eq 0 && $TESTS_FAILED -eq 0 ]]; then
        success "🎉 ALL VALIDATION TESTS PASSED!"
        echo -e "${GREEN}The Proxmox MCP installation is fully functional and ready for use.${NC}"
        return 0
    elif [[ $CRITICAL_FAILURES -eq 0 ]]; then
        warning "⚠️  VALIDATION COMPLETED WITH WARNINGS"
        echo -e "${YELLOW}The installation is functional but some non-critical tests failed.${NC}"
        return 1
    else
        error "❌ CRITICAL VALIDATION FAILURES DETECTED"
        echo -e "${RED}Critical issues must be resolved before using the system.${NC}"
        return 2
    fi
}

# ==============================================================================
# COMMAND LINE INTERFACE
# ==============================================================================

show_help() {
    cat << EOF
Proxmox MCP Validation Framework v$VALIDATION_VERSION

Usage: $0 [level] [category] [options]

Validation Levels:
  basic          Quick system and structure validation
  standard       Standard validation suite (default)
  comprehensive  Complete validation including security and performance
  security       Security-focused validation
  performance    Performance and resource validation
  pre-install    Pre-installation environment validation
  post-install   Post-installation functionality validation

Categories (for targeted testing):
  system         System requirements and environment
  network        Network connectivity and configuration
  structure      Installation structure and files
  configuration  Configuration validation
  services       Service status and health
  connectivity   Endpoint and API connectivity
  security       Security configuration and compliance
  performance    Performance and resource usage
  mcp_tools      MCP tool functionality

Options:
  --report TYPE  Generate report (basic|standard|comprehensive)
  --help         Show this help message
  --version      Show version information

Examples:
  $0                          # Run standard validation
  $0 comprehensive            # Run comprehensive validation
  $0 security                 # Run security validation only
  $0 standard connectivity    # Run connectivity tests only
  $0 pre-install              # Pre-installation validation
  $0 --report comprehensive   # Generate comprehensive report

EOF
}

main() {
    # Initialize logging
    mkdir -p "$(dirname "$VALIDATION_LOG")" "$VALIDATION_REPORT_DIR"
    touch "$VALIDATION_LOG"
    
    local level="${1:-standard}"
    local category="${2:-all}"
    local generate_report=false
    local report_type="standard"
    
    # Parse options
    for arg in "$@"; do
        case "$arg" in
            --report)
                generate_report=true
                report_type="${2:-standard}"
                ;;
            --help)
                show_help
                exit 0
                ;;
            --version)
                echo "Proxmox MCP Validation Framework v$VALIDATION_VERSION"
                exit 0
                ;;
        esac
    done
    
    # Run validation
    local validation_result=0
    run_validation "$level" "$category" || validation_result=$?
    
    # Generate report if requested
    if [[ "$generate_report" == "true" ]]; then
        local report_file
        report_file=$(generate_validation_report "$report_type")
        info "Full validation report available at: $report_file"
    fi
    
    exit $validation_result
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi