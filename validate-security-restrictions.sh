#!/bin/bash

# Proxmox MCP Security Validation Script
# This script validates that the restricted sudoers configuration properly blocks dangerous operations
# while allowing necessary Proxmox administration tasks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to print test results
print_test_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name (Expected: $expected, Got: $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to test if a command is blocked
test_blocked_command() {
    local cmd="$1"
    local description="$2"
    
    echo -e "${BLUE}Testing blocked command:${NC} $description"
    
    # Test with sudo -l to see if command is allowed
    if sudo -l "$cmd" &>/dev/null; then
        print_test_result "$description" "BLOCKED" "ALLOWED"
        echo -e "${YELLOW}  Command: $cmd${NC}"
    else
        print_test_result "$description" "BLOCKED" "BLOCKED"
    fi
}

# Function to test if a command is allowed
test_allowed_command() {
    local cmd="$1"
    local description="$2"
    
    echo -e "${BLUE}Testing allowed command:${NC} $description"
    
    # Test with sudo -l to see if command is allowed
    if sudo -l "$cmd" &>/dev/null; then
        print_test_result "$description" "ALLOWED" "ALLOWED"
    else
        print_test_result "$description" "ALLOWED" "BLOCKED"
        echo -e "${YELLOW}  Command: $cmd${NC}"
    fi
}

echo "=============================================="
echo "Proxmox MCP Security Validation Script"
echo "=============================================="
echo ""

# Verify current user
if [ "$(whoami)" != "claude-user" ]; then
    echo -e "${RED}ERROR: This script must be run as claude-user${NC}"
    exit 1
fi

echo -e "${BLUE}Current user:${NC} $(whoami)"
echo -e "${BLUE}User ID:${NC} $(id)"
echo ""

echo "=============================================="
echo "TESTING BLOCKED OPERATIONS"
echo "=============================================="

# Test blocked root@pam modifications
test_blocked_command "/usr/sbin/pveum user modify root@pam" "Block root@pam user modification"
test_blocked_command "/usr/sbin/pveum user delete root@pam" "Block root@pam user deletion"
test_blocked_command "/usr/sbin/pveum token delete root@pam!mcp-token" "Block root@pam token deletion"

# Test blocked system critical operations
test_blocked_command "/usr/bin/rm -rf /boot" "Block /boot directory deletion"
test_blocked_command "/usr/bin/rm -rf /usr/sbin/pveum" "Block critical binary deletion"
test_blocked_command "/usr/bin/chmod 000 /usr/sbin/pveum" "Block critical binary permission change"

# Test blocked node deletion
test_blocked_command "/usr/sbin/pvecm delnode" "Block node deletion"
test_blocked_command "/usr/sbin/pvesh delete /nodes/pm" "Block node deletion via API"

# Test blocked dangerous system operations
test_blocked_command "/usr/bin/dd if=/dev/zero of=/dev/sda" "Block disk wiping"
test_blocked_command "/usr/sbin/mkfs.ext4 /dev/sda1" "Block filesystem creation on system disk"
test_blocked_command "/usr/bin/systemctl stop pve-cluster" "Block critical service stop"

echo ""
echo "=============================================="
echo "TESTING ALLOWED OPERATIONS"
echo "=============================================="

# Test allowed VM management
test_allowed_command "/usr/sbin/qm list" "Allow VM listing"
test_allowed_command "/usr/sbin/pct list" "Allow container listing"
test_allowed_command "/usr/sbin/pvesh get /nodes/pm/qemu" "Allow VM API access"

# Test allowed storage management
test_allowed_command "/usr/sbin/pvesm status" "Allow storage status"
test_allowed_command "/usr/sbin/zfs list" "Allow ZFS listing"
test_allowed_command "/usr/sbin/lvs" "Allow LVM listing"

# Test allowed network management
test_allowed_command "/usr/sbin/pvesh get /nodes/pm/network" "Allow network API access"
test_allowed_command "/usr/sbin/ip link show" "Allow network interface listing"

# Test allowed monitoring
test_allowed_command "/usr/sbin/pvesh get /nodes/pm/status" "Allow node status check"
test_allowed_command "/usr/bin/systemctl status pveproxy" "Allow service status check"
test_allowed_command "/usr/bin/journalctl -u pvedaemon" "Allow log access"

# Test allowed user management (non-root)
test_allowed_command "/usr/sbin/pveum user list" "Allow user listing"
test_allowed_command "/usr/sbin/pveum user add testuser@pam" "Allow non-root user creation"
test_allowed_command "/usr/sbin/pveum role list" "Allow role listing"

# Test allowed system administration
test_allowed_command "/usr/bin/systemctl status" "Allow system status check"
test_allowed_command "/usr/bin/ps aux" "Allow process listing"
test_allowed_command "/usr/bin/df -h" "Allow disk usage check"
test_allowed_command "/usr/bin/free -m" "Allow memory usage check"

echo ""
echo "=============================================="
echo "ADDITIONAL SECURITY CHECKS"
echo "=============================================="

# Check if user can become root without restrictions
echo -e "${BLUE}Testing root access restriction:${NC}"
if sudo -l | grep -q "ALL.*ALL.*ALL"; then
    print_test_result "Unrestricted root access" "BLOCKED" "ALLOWED"
    echo -e "${YELLOW}  WARNING: User has unrestricted sudo access${NC}"
else
    print_test_result "Unrestricted root access" "BLOCKED" "BLOCKED"
fi

# Check if user can edit sudoers
echo -e "${BLUE}Testing sudoers modification:${NC}"
if sudo -l | grep -q "visudo\|/etc/sudoers"; then
    print_test_result "Sudoers modification" "BLOCKED" "ALLOWED"
else
    print_test_result "Sudoers modification" "BLOCKED" "BLOCKED"
fi

# Check if user can modify critical Proxmox config files
echo -e "${BLUE}Testing critical config modification:${NC}"
if [ -w "/etc/pve/user.cfg" ] || sudo -l | grep -q "/etc/pve"; then
    print_test_result "Critical config modification" "RESTRICTED" "ALLOWED"
else
    print_test_result "Critical config modification" "RESTRICTED" "RESTRICTED"
fi

echo ""
echo "=============================================="
echo "TEST SUMMARY"
echo "=============================================="
echo -e "Total tests: ${BLUE}$TESTS_TOTAL${NC}"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ ALL SECURITY TESTS PASSED${NC}"
    echo "The restricted sudoers configuration is working correctly."
    exit 0
else
    echo -e "\n${RED}✗ SECURITY TESTS FAILED${NC}"
    echo "The restricted sudoers configuration needs review."
    exit 1
fi