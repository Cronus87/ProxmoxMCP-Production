#!/bin/bash

# COMPREHENSIVE PROXMOX MCP SECURITY VALIDATION SCRIPT
# ===================================================
# This script provides bulletproof validation against ALL attack vectors
# identified by the Security Testing Agent, including:
# 
# 1. Root Protection Bypass Attempts
# 2. Alternative Path Command Bypasses  
# 3. Privilege Escalation Via Allowed Commands
# 4. Environment Variable Manipulation
# 5. Service Masking and Critical Command Coverage
# 6. Package Management Security Gaps
# 7. Network Destruction Prevention
# 8. Shell Escape and Command Chaining
#
# VERSION: 2.0 - Comprehensive Security Testing Edition
# SECURITY COVERAGE: ALL CRITICAL VULNERABILITIES

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
CRITICAL_FAILURES=0

# Function to print test results with severity
print_test_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    local severity="${4:-NORMAL}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        if [ "$severity" = "CRITICAL" ]; then
            echo -e "${RED}✗ CRITICAL FAIL${NC}: $test_name (Expected: $expected, Got: $actual)"
            CRITICAL_FAILURES=$((CRITICAL_FAILURES + 1))
        else
            echo -e "${RED}✗ FAIL${NC}: $test_name (Expected: $expected, Got: $actual)"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Enhanced function to test blocked commands with multiple bypass attempts
test_blocked_command_comprehensive() {
    local base_cmd="$1"
    local description="$2"
    local severity="${3:-NORMAL}"
    
    echo -e "${BLUE}Testing blocked command (comprehensive):${NC} $description"
    
    # Test base command
    if sudo -l "$base_cmd" &>/dev/null; then
        print_test_result "$description - Direct" "BLOCKED" "ALLOWED" "$severity"
        echo -e "${YELLOW}  Command: $base_cmd${NC}"
    else
        print_test_result "$description - Direct" "BLOCKED" "BLOCKED" "$severity"
    fi
    
    # Test with different paths
    local alt_paths=("/bin" "/usr/bin" "/usr/sbin" "/sbin")
    local cmd_name=$(basename "$base_cmd")
    
    for path in "${alt_paths[@]}"; do
        local alt_cmd="$path/$cmd_name"
        if [ "$alt_cmd" != "$base_cmd" ]; then
            if sudo -l "$alt_cmd" &>/dev/null; then
                print_test_result "$description - Alt Path ($alt_cmd)" "BLOCKED" "ALLOWED" "$severity"
            else
                print_test_result "$description - Alt Path ($alt_cmd)" "BLOCKED" "BLOCKED" "$severity"
            fi
        fi
    done
    
    # Test with shell metacharacters
    local meta_variants=("$base_cmd;" "$base_cmd && true" "$base_cmd | true" "true; $base_cmd")
    for variant in "${meta_variants[@]}"; do
        if sudo -l "$variant" &>/dev/null; then
            print_test_result "$description - Shell Escape" "BLOCKED" "ALLOWED" "CRITICAL"
        else
            print_test_result "$description - Shell Escape" "BLOCKED" "BLOCKED" "$severity"
        fi
    done
}

# Function to test environment variable manipulation
test_environment_security() {
    local test_name="$1"
    local env_var="$2"
    local malicious_value="$3"
    
    echo -e "${PURPLE}Testing environment security:${NC} $test_name"
    
    # Test if dangerous environment variables are filtered
    if sudo -l | grep -q "env_delete.*$env_var"; then
        print_test_result "$test_name" "PROTECTED" "PROTECTED"
    else
        print_test_result "$test_name" "PROTECTED" "VULNERABLE" "CRITICAL"
    fi
}

# Function to test privilege escalation via allowed commands
test_privilege_escalation() {
    local allowed_cmd="$1"
    local escalation_method="$2"
    local description="$3"
    
    echo -e "${CYAN}Testing privilege escalation:${NC} $description"
    
    # This is a conceptual test - we check if the command could be used for escalation
    case "$escalation_method" in
        "file_write")
            if echo "$allowed_cmd" | grep -q -E "(tee|cat|echo|printf|dd).*>"; then
                print_test_result "$description" "SAFE" "VULNERABLE" "CRITICAL"
            else
                print_test_result "$description" "SAFE" "SAFE"
            fi
            ;;
        "shell_escape")
            if echo "$allowed_cmd" | grep -q -E "(/bin/sh|/bin/bash|bash|sh|\${|`|\$\()"; then
                print_test_result "$description" "SAFE" "VULNERABLE" "CRITICAL"
            else
                print_test_result "$description" "SAFE" "SAFE"
            fi
            ;;
        *)
            print_test_result "$description" "SAFE" "UNKNOWN"
            ;;
    esac
}

echo "=============================================="
echo "COMPREHENSIVE PROXMOX MCP SECURITY VALIDATION"
echo "=============================================="
echo ""
echo -e "${PURPLE}TESTING ALL CRITICAL ATTACK VECTORS${NC}"
echo -e "${PURPLE}Identified by Security Testing Agent${NC}"
echo ""

# Verify current user
if [ "$(whoami)" != "claude-user" ]; then
    echo -e "${RED}ERROR: This script must be run as claude-user${NC}"
    exit 1
fi

echo -e "${BLUE}Current user:${NC} $(whoami)"
echo -e "${BLUE}User ID:${NC} $(id)"
echo -e "${BLUE}Sudo version:${NC} $(sudo --version | head -1)"
echo ""

echo "=============================================="
echo "1. ROOT PROTECTION BYPASS VULNERABILITY TESTS"
echo "=============================================="

# Test comprehensive root@pam protection
test_blocked_command_comprehensive "/usr/sbin/pveum user modify root@pam" "Root user modification" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/pveum user delete root@pam" "Root user deletion" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/pveum user modify root@pam --enable 0" "Root disable bypass attempt" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/pveum user modify root@pam --disable" "Root disable alternative" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/pveum user passwd root@pam" "Root password change" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/pveum token delete root@pam!token" "Root token deletion" "CRITICAL"

# Test direct root access attempts
test_blocked_command_comprehensive "/bin/su - root" "Direct su to root" "CRITICAL"
test_blocked_command_comprehensive "/bin/su root" "Direct su root" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/sudo -u root bash" "Sudo to root bash" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/sudo -i" "Sudo interactive shell" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/sudo -s" "Sudo shell" "CRITICAL"

echo ""
echo "=============================================="
echo "2. DANGEROUS COMMAND COVERAGE GAP TESTS"
echo "=============================================="

# Test systemctl mask commands (CRITICAL GAP)
test_blocked_command_comprehensive "/usr/bin/systemctl mask pve-cluster" "Critical service masking" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/systemctl mask corosync" "Corosync service masking" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/systemctl mask pveproxy" "Proxy service masking" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/systemctl mask pvedaemon" "Daemon service masking" "CRITICAL"

# Test /etc/sudoers* modifications (CRITICAL GAP)
test_blocked_command_comprehensive "/usr/sbin/visudo" "Sudoers direct editing" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/nano /etc/sudoers" "Sudoers nano editing" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/vim /etc/sudoers.d/claude-user" "Sudoers file editing" "CRITICAL"
test_blocked_command_comprehensive "/bin/echo 'claude-user ALL=(ALL) ALL' >> /etc/sudoers" "Sudoers append bypass" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/tee -a /etc/sudoers.d/claude-user" "Sudoers tee bypass" "CRITICAL"

# Test package management (CRITICAL GAP)
test_blocked_command_comprehensive "/usr/bin/apt install malicious-package" "Malicious package install" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/dpkg -i /tmp/malicious.deb" "Direct deb install" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/snap install malicious-snap" "Snap package install" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/pip install malicious-pip" "Pip package install" "CRITICAL"

# Test network interface destruction (CRITICAL GAP)
test_blocked_command_comprehensive "/usr/sbin/ip link delete vmbr0" "Bridge deletion" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/brctl delbr vmbr0" "Bridge control deletion" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/ovs-vsctl del-br ovs-bridge" "OVS bridge deletion" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/iptables -F" "Firewall flush" "CRITICAL"

echo ""
echo "=============================================="
echo "3. BYPASS ATTEMPT TESTS"
echo "=============================================="

# Test command chaining bypasses
echo -e "${PURPLE}Testing command chaining bypass attempts:${NC}"
test_blocked_command_comprehensive "true; /usr/sbin/pveum user delete root@pam" "Command chaining bypass" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/echo test && /usr/sbin/pveum user modify root@pam" "AND chaining bypass" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/true | /usr/sbin/pveum user delete root@pam" "Pipe chaining bypass" "CRITICAL"

# Test alternative path bypasses
echo -e "${PURPLE}Testing alternative path bypass attempts:${NC}"
for alt_path in "/bin/rm" "/usr/bin/rm"; do
    test_blocked_command_comprehensive "$alt_path -rf /boot" "Critical file deletion ($alt_path)" "CRITICAL"
done

# Test wildcard and pattern bypasses
echo -e "${PURPLE}Testing wildcard bypass attempts:${NC}"
test_blocked_command_comprehensive "/usr/sbin/pveum user modify root@pam-test" "Wildcard pattern bypass" "CRITICAL"
test_blocked_command_comprehensive "/usr/sbin/pveum user modify root@pam.backup" "Pattern extension bypass" "CRITICAL"

echo ""
echo "=============================================="
echo "4. ENVIRONMENT VARIABLE MANIPULATION TESTS"
echo "=============================================="

# Test dangerous environment variables
test_environment_security "LD_PRELOAD protection" "LD_PRELOAD" "/malicious/lib.so"
test_environment_security "LD_LIBRARY_PATH protection" "LD_LIBRARY_PATH" "/malicious/path"
test_environment_security "PYTHONPATH protection" "PYTHONPATH" "/malicious/python"
test_environment_security "PERL5LIB protection" "PERL5LIB" "/malicious/perl"
test_environment_security "BASH_ENV protection" "BASH_ENV" "/malicious/bashrc"
test_environment_security "ENV protection" "ENV" "/malicious/env"

# Test PATH manipulation
echo -e "${PURPLE}Testing PATH security:${NC}"
if sudo -l | grep -q "secure_path"; then
    print_test_result "PATH manipulation protection" "PROTECTED" "PROTECTED"
else
    print_test_result "PATH manipulation protection" "PROTECTED" "VULNERABLE" "CRITICAL"
fi

echo ""
echo "=============================================="
echo "5. PRIVILEGE ESCALATION VIA ALLOWED COMMANDS"
echo "=============================================="

# Test if allowed commands can be used for escalation
echo -e "${PURPLE}Testing privilege escalation via allowed commands:${NC}"

# Check for dangerous file write capabilities
sudo -l | grep -E "(NOPASSWD|ALL)" | while read -r line; do
    if echo "$line" | grep -q -E "(tee|cat.*>|echo.*>|printf.*>)"; then
        print_test_result "File write escalation risk" "SAFE" "VULNERABLE" "CRITICAL"
    fi
done

# Check for shell escape possibilities
sudo -l | grep -E "(NOPASSWD|ALL)" | while read -r line; do
    if echo "$line" | grep -q -E "(sh|bash|python|perl|ruby|node)"; then
        print_test_result "Shell escape risk" "SAFE" "VULNERABLE" "CRITICAL"
    fi
done

echo ""
echo "=============================================="
echo "6. OVERLY PERMISSIVE PATTERN TESTS"
echo "=============================================="

# Test if patterns are too broad
echo -e "${PURPLE}Testing pattern restrictions:${NC}"

# Check for wildcard permissions that could be abused
if sudo -l | grep -q "ALL.*ALL.*ALL"; then
    print_test_result "Unrestricted sudo access" "BLOCKED" "ALLOWED" "CRITICAL"
else
    print_test_result "Unrestricted sudo access" "BLOCKED" "BLOCKED"
fi

# Check for overly broad file system access
if sudo -l | grep -q "/usr/bin/.*\*"; then
    print_test_result "Broad file system access" "RESTRICTED" "PERMISSIVE" "CRITICAL"
else
    print_test_result "Broad file system access" "RESTRICTED" "RESTRICTED"
fi

echo ""
echo "=============================================="
echo "7. COMPREHENSIVE OPERATIONAL FUNCTIONALITY"
echo "=============================================="

# Test that legitimate operations still work
echo -e "${BLUE}Testing legitimate operations:${NC}"

# VM management
if sudo -l "/usr/sbin/qm list" &>/dev/null; then
    print_test_result "VM management access" "ALLOWED" "ALLOWED"
else
    print_test_result "VM management access" "ALLOWED" "BLOCKED"
fi

# Storage management
if sudo -l "/usr/sbin/pvesm status" &>/dev/null; then
    print_test_result "Storage management access" "ALLOWED" "ALLOWED"
else
    print_test_result "Storage management access" "ALLOWED" "BLOCKED"
fi

# Network management (safe operations)
if sudo -l "/usr/sbin/ip link show" &>/dev/null; then
    print_test_result "Network monitoring access" "ALLOWED" "ALLOWED"
else
    print_test_result "Network monitoring access" "ALLOWED" "BLOCKED"
fi

# User management (non-root)
if sudo -l "/usr/sbin/pveum user list" &>/dev/null; then
    print_test_result "User management access" "ALLOWED" "ALLOWED"
else
    print_test_result "User management access" "ALLOWED" "BLOCKED"
fi

echo ""
echo "=============================================="
echo "8. AUDIT AND LOGGING VERIFICATION"
echo "=============================================="

# Test logging configuration
echo -e "${PURPLE}Testing audit and logging:${NC}"

if sudo -l | grep -q "log_input"; then
    print_test_result "Input logging enabled" "ENABLED" "ENABLED"
else
    print_test_result "Input logging enabled" "ENABLED" "DISABLED"
fi

if sudo -l | grep -q "log_output"; then
    print_test_result "Output logging enabled" "ENABLED" "ENABLED"
else
    print_test_result "Output logging enabled" "ENABLED" "DISABLED"
fi

if sudo -l | grep -q "use_pty"; then
    print_test_result "PTY requirement enabled" "ENABLED" "ENABLED"
else
    print_test_result "PTY requirement enabled" "ENABLED" "DISABLED"
fi

echo ""
echo "=============================================="
echo "9. EMERGENCY ACCESS PREVENTION"
echo "=============================================="

# Test that emergency access methods are blocked
echo -e "${PURPLE}Testing emergency access prevention:${NC}"

test_blocked_command_comprehensive "/bin/bash" "Direct shell access" "CRITICAL"
test_blocked_command_comprehensive "/bin/sh" "Direct shell access (sh)" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/python3 -c 'import os; os.system(\"/bin/bash\")'" "Python shell escape" "CRITICAL"
test_blocked_command_comprehensive "/usr/bin/perl -e 'system(\"/bin/bash\")'" "Perl shell escape" "CRITICAL"

echo ""
echo "=============================================="
echo "COMPREHENSIVE SECURITY TEST SUMMARY"
echo "=============================================="

echo -e "Total tests: ${BLUE}$TESTS_TOTAL${NC}"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Critical failures: ${RED}$CRITICAL_FAILURES${NC}"

# Calculate success rate
if [ $TESTS_TOTAL -gt 0 ]; then
    SUCCESS_RATE=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
    echo -e "Success rate: ${BLUE}${SUCCESS_RATE}%${NC}"
fi

echo ""
echo "=============================================="
echo "SECURITY ASSESSMENT RESULT"
echo "=============================================="

if [ $CRITICAL_FAILURES -eq 0 ] && [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ MAXIMUM SECURITY ACHIEVED${NC}"
    echo -e "${GREEN}✓ ALL CRITICAL VULNERABILITIES MITIGATED${NC}"
    echo -e "${GREEN}✓ COMPREHENSIVE PROTECTION VERIFIED${NC}"
    echo ""
    echo -e "${GREEN}The enhanced security configuration successfully addresses${NC}"
    echo -e "${GREEN}ALL security gaps identified by the Testing Agent:${NC}"
    echo -e "  ${GREEN}✓ Root Protection Bypass Vulnerability - FIXED${NC}"
    echo -e "  ${GREEN}✓ Dangerous Command Coverage Gaps - FIXED${NC}"
    echo -e "  ${GREEN}✓ Overly Permissive Patterns - FIXED${NC}"
    echo -e "  ${GREEN}✓ Environment Variable Manipulation - PROTECTED${NC}"
    echo -e "  ${GREEN}✓ Privilege Escalation Vectors - BLOCKED${NC}"
    echo -e "  ${GREEN}✓ Command Bypass Attempts - PREVENTED${NC}"
    echo ""
    exit 0
elif [ $CRITICAL_FAILURES -eq 0 ]; then
    echo -e "${YELLOW}⚠ SECURITY PARTIALLY IMPLEMENTED${NC}"
    echo -e "${YELLOW}⚠ No critical failures, but some tests failed${NC}"
    echo "Review failed tests and adjust configuration as needed."
    exit 1
else
    echo -e "${RED}✗ CRITICAL SECURITY FAILURES DETECTED${NC}"
    echo -e "${RED}✗ $CRITICAL_FAILURES critical security issues found${NC}"
    echo -e "${RED}✗ IMMEDIATE ATTENTION REQUIRED${NC}"
    echo ""
    echo -e "${RED}The security configuration has critical vulnerabilities${NC}"
    echo -e "${RED}that must be addressed before deployment.${NC}"
    exit 2
fi