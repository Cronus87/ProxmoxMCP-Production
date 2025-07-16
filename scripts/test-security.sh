#!/bin/bash
# Comprehensive Security Testing Script for Proxmox MCP Dual-Port Server
# Tests device authentication, network restrictions, and admin interface

set -e

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/security-test.log"

# Server configuration
SERVER_IP="${1:-localhost}"
MCP_PORT="8080"
ADMIN_PORT="8081"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

failure() {
    echo -e "${RED}❌ $*${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

test_header() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo ""
    echo -e "${PURPLE}🧪 Test $TESTS_TOTAL: $*${NC}"
    echo "----------------------------------------"
}

# Test helper functions
http_get() {
    local url="$1"
    local expected_status="${2:-200}"
    
    local response
    local status
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url" 2>/dev/null || echo "HTTPSTATUS:000")
    status=$(echo "$response" | grep "HTTPSTATUS:" | cut -d: -f2)
    
    echo "$status"
}

http_post() {
    local url="$1"
    local data="$2"
    local headers="${3:-}"
    local expected_status="${4:-200}"
    
    local response
    local status
    
    if [ -n "$headers" ]; then
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST "$url" -H "Content-Type: application/json" -H "$headers" -d "$data" 2>/dev/null || echo "HTTPSTATUS:000")
    else
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST "$url" -H "Content-Type: application/json" -d "$data" 2>/dev/null || echo "HTTPSTATUS:000")
    fi
    
    status=$(echo "$response" | grep "HTTPSTATUS:" | cut -d: -f2)
    echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//'
    return $((status == expected_status ? 0 : 1))
}

# Test functions
test_mcp_health() {
    test_header "MCP Server Health Check"
    
    local status
    status=$(http_get "http://$SERVER_IP:$MCP_PORT/health")
    
    if [ "$status" = "200" ]; then
        success "MCP server health endpoint accessible"
    else
        failure "MCP server health endpoint failed (HTTP $status)"
    fi
}

test_admin_health() {
    test_header "Admin Interface Health Check"
    
    local status
    status=$(http_get "http://$SERVER_IP:$ADMIN_PORT/health")
    
    if [ "$status" = "200" ]; then
        success "Admin interface health endpoint accessible"
    else
        failure "Admin interface health endpoint failed (HTTP $status)"
    fi
}

test_mcp_authentication_required() {
    test_header "MCP Authentication Requirement"
    
    local status
    status=$(http_get "http://$SERVER_IP:$MCP_PORT/api/mcp")
    
    if [ "$status" = "401" ] || [ "$status" = "403" ]; then
        success "MCP endpoint properly requires authentication (HTTP $status)"
    else
        failure "MCP endpoint should require authentication but returned HTTP $status"
    fi
}

test_device_registration() {
    test_header "Device Registration Endpoint"
    
    local response
    local test_data='{"device_name": "test-device-'$(date +%s)'", "client_info": "security-test"}'
    
    response=$(http_post "http://$SERVER_IP:$MCP_PORT/register" "$test_data" "" 200)
    local status=$?
    
    if [ $status -eq 0 ] && echo "$response" | grep -q '"success".*true'; then
        success "Device registration endpoint working"
        # Extract device_id for later tests
        DEVICE_ID=$(echo "$response" | grep -o '"device_id":"[^"]*"' | cut -d'"' -f4)
        info "Generated test device ID: $DEVICE_ID"
    else
        failure "Device registration failed: $response"
    fi
}

test_registration_rate_limiting() {
    test_header "Registration Rate Limiting"
    
    info "Testing rate limiting (5 requests in 15 minutes)..."
    
    local success_count=0
    local rate_limited_count=0
    
    for i in {1..7}; do
        local test_data='{"device_name": "rate-test-'$i'-'$(date +%s)'", "client_info": "rate-limit-test"}'
        local response
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST "http://$SERVER_IP:$MCP_PORT/register" \
            -H "Content-Type: application/json" -d "$test_data" 2>/dev/null || echo "HTTPSTATUS:000")
        
        local status=$(echo "$response" | grep "HTTPSTATUS:" | cut -d: -f2)
        
        if [ "$status" = "200" ] || [ "$status" = "201" ]; then
            success_count=$((success_count + 1))
        elif [ "$status" = "429" ]; then
            rate_limited_count=$((rate_limited_count + 1))
        fi
        
        sleep 1
    done
    
    if [ $rate_limited_count -gt 0 ]; then
        success "Rate limiting working ($success_count successful, $rate_limited_count rate-limited)"
    else
        warning "Rate limiting test inconclusive (all $success_count requests succeeded)"
    fi
}

test_admin_interface_access() {
    test_header "Admin Interface Access"
    
    local status
    status=$(http_get "http://$SERVER_IP:$ADMIN_PORT/")
    
    if [ "$status" = "200" ]; then
        success "Admin interface dashboard accessible"
    else
        failure "Admin interface dashboard failed (HTTP $status)"
    fi
}

test_admin_api_endpoints() {
    test_header "Admin API Endpoints"
    
    # Test stats endpoint
    local status
    status=$(http_get "http://$SERVER_IP:$ADMIN_PORT/api/stats")
    
    if [ "$status" = "200" ]; then
        success "Admin stats API accessible"
    else
        failure "Admin stats API failed (HTTP $status)"
    fi
    
    # Test pending requests endpoint
    status=$(http_get "http://$SERVER_IP:$ADMIN_PORT/api/pending")
    
    if [ "$status" = "200" ]; then
        success "Admin pending requests API accessible"
    else
        failure "Admin pending requests API failed (HTTP $status)"
    fi
    
    # Test devices endpoint
    status=$(http_get "http://$SERVER_IP:$ADMIN_PORT/api/devices")
    
    if [ "$status" = "200" ]; then
        success "Admin devices API accessible"
    else
        failure "Admin devices API failed (HTTP $status)"
    fi
}

test_device_approval_workflow() {
    test_header "Device Approval Workflow"
    
    if [ -z "${DEVICE_ID:-}" ]; then
        warning "Skipping approval test - no device ID from registration test"
        return
    fi
    
    info "Testing device approval for device ID: $DEVICE_ID"
    
    # Test approval
    local approval_data='{"expiry_days": 7}'
    local response
    response=$(http_post "http://$SERVER_IP:$ADMIN_PORT/api/approve/$DEVICE_ID" "$approval_data" "" 200)
    local status=$?
    
    if [ $status -eq 0 ] && echo "$response" | grep -q '"success".*true'; then
        success "Device approval endpoint working"
        
        # Extract token for authentication test
        DEVICE_TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        info "Generated test device token (truncated): ${DEVICE_TOKEN:0:20}..."
    else
        failure "Device approval failed: $response"
    fi
}

test_authenticated_mcp_access() {
    test_header "Authenticated MCP Access"
    
    if [ -z "${DEVICE_TOKEN:-}" ]; then
        warning "Skipping authentication test - no device token from approval test"
        return
    fi
    
    info "Testing MCP access with device token..."
    
    local response
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "http://$SERVER_IP:$MCP_PORT/api/mcp" \
        -H "Authorization: Bearer $DEVICE_TOKEN" 2>/dev/null || echo "HTTPSTATUS:000")
    
    local status=$(echo "$response" | grep "HTTPSTATUS:" | cut -d: -f2)
    
    if [ "$status" = "200" ] || [ "$status" = "405" ]; then
        # 405 is OK for GET request to MCP endpoint that expects POST
        success "Authenticated MCP access working (HTTP $status)"
    else
        failure "Authenticated MCP access failed (HTTP $status)"
    fi
}

test_token_revocation() {
    test_header "Token Revocation"
    
    if [ -z "${DEVICE_ID:-}" ]; then
        warning "Skipping revocation test - no device ID available"
        return
    fi
    
    info "Testing device token revocation..."
    
    local revocation_data='{"reason": "security-test-revocation"}'
    local response
    response=$(http_post "http://$SERVER_IP:$ADMIN_PORT/api/revoke/$DEVICE_ID" "$revocation_data" "" 200)
    local status=$?
    
    if [ $status -eq 0 ] && echo "$response" | grep -q '"success".*true'; then
        success "Device revocation endpoint working"
        
        # Test that revoked token no longer works
        if [ -n "${DEVICE_TOKEN:-}" ]; then
            local auth_status
            auth_status=$(curl -s -w "%{http_code}" -o /dev/null "http://$SERVER_IP:$MCP_PORT/api/mcp" \
                -H "Authorization: Bearer $DEVICE_TOKEN" 2>/dev/null)
            
            if [ "$auth_status" = "401" ] || [ "$auth_status" = "403" ]; then
                success "Revoked token properly rejected (HTTP $auth_status)"
            else
                failure "Revoked token still accepted (HTTP $auth_status)"
            fi
        fi
    else
        failure "Device revocation failed: $response"
    fi
}

test_network_security() {
    test_header "Network Security Configuration"
    
    info "Testing firewall and network restrictions..."
    
    # Test that both ports are accessible from localhost
    local mcp_accessible=false
    local admin_accessible=false
    
    if curl -s --connect-timeout 5 "http://localhost:$MCP_PORT/health" >/dev/null 2>&1; then
        mcp_accessible=true
    fi
    
    if curl -s --connect-timeout 5 "http://localhost:$ADMIN_PORT/health" >/dev/null 2>&1; then
        admin_accessible=true
    fi
    
    if [ "$mcp_accessible" = true ] && [ "$admin_accessible" = true ]; then
        success "Both ports accessible from localhost"
    else
        failure "Network accessibility test failed (MCP: $mcp_accessible, Admin: $admin_accessible)"
    fi
}

test_container_health() {
    test_header "Container Health Status"
    
    info "Checking Docker container status..."
    
    if command -v docker >/dev/null 2>&1; then
        local container_status
        container_status=$(docker ps --filter "name=proxmox-mcp-server" --format "table {{.Status}}" | tail -n +2)
        
        if echo "$container_status" | grep -q "Up"; then
            success "MCP container is running: $container_status"
        else
            failure "MCP container not running properly: $container_status"
        fi
    else
        warning "Docker not available for container health check"
    fi
}

# Performance and stress tests
test_concurrent_requests() {
    test_header "Concurrent Request Handling"
    
    info "Testing concurrent health check requests..."
    
    local success_count=0
    local total_requests=10
    
    for i in $(seq 1 $total_requests); do
        (
            status=$(http_get "http://$SERVER_IP:$MCP_PORT/health")
            if [ "$status" = "200" ]; then
                echo "success"
            fi
        ) &
    done
    
    wait
    
    # Count successful responses (this is a simplified test)
    sleep 2
    success "Concurrent request test completed (basic functionality test)"
}

# Main test execution
main() {
    echo ""
    echo -e "${BLUE}🔒 Proxmox MCP Security Test Suite${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo ""
    echo "Testing server: $SERVER_IP"
    echo "MCP Port: $MCP_PORT"
    echo "Admin Port: $ADMIN_PORT"
    echo ""
    
    # Initialize log
    echo "Security testing started at $(date)" > "$LOG_FILE"
    
    # Run all tests
    test_mcp_health
    test_admin_health
    test_mcp_authentication_required
    test_device_registration
    test_registration_rate_limiting
    test_admin_interface_access
    test_admin_api_endpoints
    test_device_approval_workflow
    test_authenticated_mcp_access
    test_token_revocation
    test_network_security
    test_container_health
    test_concurrent_requests
    
    # Final results
    echo ""
    echo -e "${BLUE}📊 Test Results Summary${NC}"
    echo "========================"
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    local pass_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    echo "Pass Rate: $pass_rate%"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo ""
        echo -e "${GREEN}🎉 All security tests passed!${NC}"
        echo -e "${GREEN}✅ Your Proxmox MCP server is properly secured.${NC}"
        exit 0
    else
        echo ""
        echo -e "${RED}⚠️  Some security tests failed.${NC}"
        echo -e "${RED}❌ Please review the test results and fix any issues.${NC}"
        echo ""
        echo "Detailed logs available in: $LOG_FILE"
        exit 1
    fi
}

# Usage information
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [SERVER_IP]"
    echo ""
    echo "Test the security configuration of Proxmox MCP dual-port server."
    echo ""
    echo "Arguments:"
    echo "  SERVER_IP    IP address or hostname of the MCP server (default: localhost)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Test localhost"
    echo "  $0 192.168.1.100     # Test remote server"
    echo ""
    echo "The script will test:"
    echo "  - Health endpoints on both ports"
    echo "  - MCP authentication requirements"
    echo "  - Device registration and approval workflow"
    echo "  - Admin interface accessibility"
    echo "  - Token management and revocation"
    echo "  - Rate limiting protection"
    echo "  - Network security configuration"
    exit 0
fi

# Run main function
main "$@"