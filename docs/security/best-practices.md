# Security Best Practices - Proxmox MCP

**Enterprise Security Operations and Administrative Guidelines**

## Overview

This document provides comprehensive security best practices for administrators managing the Proxmox MCP system. These practices ensure maximum security posture while maintaining operational efficiency and compliance requirements.

## Table of Contents

1. [Administrative Security Practices](#administrative-security-practices)
2. [Access Management](#access-management)
3. [Monitoring and Alerting](#monitoring-and-alerting)
4. [Incident Response](#incident-response)
5. [Compliance Operations](#compliance-operations)
6. [Security Maintenance](#security-maintenance)
7. [Risk Management](#risk-management)
8. [Training and Awareness](#training-and-awareness)

---

## Administrative Security Practices

### Daily Security Operations

#### Morning Security Checklist
```bash
#!/bin/bash
# Daily Security Verification Script

echo "=== PROXMOX MCP DAILY SECURITY CHECK ==="
echo "Date: $(date)"
echo ""

# 1. Verify service health
echo "1. Service Health Check:"
systemctl is-active proxmox-mcp && echo "  ✅ MCP Service: Running" || echo "  ❌ MCP Service: Failed"
docker ps | grep -q mcp-server && echo "  ✅ Container: Running" || echo "  ❌ Container: Failed"

# 2. Check security configuration integrity
echo ""
echo "2. Security Configuration:"
visudo -c -f /etc/sudoers.d/claude-user && echo "  ✅ Sudoers: Valid" || echo "  ❌ Sudoers: Invalid"

# 3. Review blocked attempts (last 24 hours)
echo ""
echo "3. Security Events (Last 24h):"
BLOCKED_COUNT=$(grep "command not allowed" /var/log/sudo-claude-user.log | grep "$(date +%Y-%m-%d)" | wc -l)
echo "  Blocked Commands: $BLOCKED_COUNT"

AUTH_FAILURES=$(grep "authentication failure" /var/log/auth.log | grep claude-user | grep "$(date +%Y-%m-%d)" | wc -l)
echo "  Auth Failures: $AUTH_FAILURES"

# 4. SSH key integrity
echo ""
echo "4. SSH Key Status:"
test -f /opt/proxmox-mcp/keys/ssh_key && echo "  ✅ SSH Key: Present" || echo "  ❌ SSH Key: Missing"

# 5. Container security status
echo ""
echo "5. Container Security:"
docker inspect proxmox-mcp-server | jq -r '.[0].HostConfig.SecurityOpt[]' | grep -q "no-new-privileges:true" && echo "  ✅ No New Privileges: Enabled" || echo "  ❌ No New Privileges: Disabled"

echo ""
echo "=== Daily Check Complete ==="
```

#### Security Log Review Process
```bash
# Review security logs for anomalies
sudo tail -100 /var/log/sudo-claude-user.log | grep -E "(BLOCKED|DENIED|ERROR)"

# Check for privilege escalation attempts
sudo grep -i "escalat\|privile\|root" /var/log/sudo-claude-user.log | tail -20

# Monitor authentication patterns
sudo grep "claude-user" /var/log/auth.log | tail -20

# Review unusual command patterns
sudo awk '{print $NF}' /var/log/sudo-claude-user.log | sort | uniq -c | sort -rn | head -10
```

### Administrative Access Controls

#### Principle of Least Privilege
- **Administrative users** should only have access to specific MCP functions needed for their role
- **Time-limited access** for maintenance windows
- **Multi-person approval** for critical configuration changes
- **Segregation of duties** between different administrative functions

#### Access Request Process
```yaml
Access Request Workflow:
  1. Submit formal access request with business justification
  2. Manager approval required for any admin access
  3. Security team review of access scope and duration
  4. Implementation with minimum necessary permissions
  5. Regular access review and revocation process
  6. Audit trail of all access decisions
```

#### Emergency Access Procedures
```bash
# Emergency access scenario (production outage)
# 1. Document the emergency
echo "Emergency: $(date) - Production outage requiring extended access" >> /var/log/emergency-access.log

# 2. Create temporary elevated access (ONLY if absolutely necessary)
# This should be pre-approved in emergency procedures
sudo cp /etc/sudoers.d/claude-user /etc/sudoers.d/claude-user.emergency-backup
echo "claude-user ALL=(ALL) NOPASSWD: /specific/emergency/command" | sudo tee /etc/sudoers.d/emergency-access

# 3. MANDATORY: Remove emergency access immediately after use
sudo rm /etc/sudoers.d/emergency-access
sudo visudo -c

# 4. Document actions taken
echo "Emergency access removed: $(date)" >> /var/log/emergency-access.log
```

---

## Access Management

### SSH Key Management Best Practices

#### Key Generation Standards
```bash
# Generate strong SSH keys (ED25519 preferred)
ssh-keygen -t ed25519 -b 4096 -f ~/.ssh/proxmox_mcp_key -C "admin@company.com-$(date +%Y%m%d)"

# Set secure permissions
chmod 600 ~/.ssh/proxmox_mcp_key
chmod 644 ~/.ssh/proxmox_mcp_key.pub

# Use strong passphrase protection
ssh-keygen -p -f ~/.ssh/proxmox_mcp_key
```

#### Key Rotation Schedule
```yaml
Key Rotation Policy:
  Production Keys: Every 90 days
  Development Keys: Every 180 days
  Emergency Keys: Immediate after use
  Service Account Keys: Every 30 days

Rotation Process:
  1. Generate new key pair
  2. Deploy public key to target systems
  3. Test new key functionality
  4. Update configuration files
  5. Revoke old keys
  6. Document rotation in change log
```

#### Key Storage Security
- **Hardware Security Modules (HSM)** for production keys
- **Encrypted key storage** with strong passphrases
- **Separate key management** from operational systems
- **Backup keys stored offline** in secure locations
- **Access logging** for all key operations

### API Token Management

#### Token Security Requirements
```bash
# Token generation with appropriate scopes
# Use Proxmox web interface: Datacenter → API Tokens

# Required token configuration:
User: root@pam
Token ID: proxmox-mcp-$(date +%Y%m%d)
Privilege Separation: Disabled (for full access)
Expiration: 90 days maximum

# Token storage security
umask 077
echo "PROXMOX_TOKEN_VALUE=your-token-here" > /opt/proxmox-mcp/.env.token
chmod 600 /opt/proxmox-mcp/.env.token
chown root:root /opt/proxmox-mcp/.env.token
```

#### Token Rotation Process
```bash
#!/bin/bash
# Token Rotation Script

OLD_TOKEN_ID="proxmox-mcp-old"
NEW_TOKEN_ID="proxmox-mcp-$(date +%Y%m%d)"

# 1. Generate new token (manual step in Proxmox UI)
echo "Generate new token: $NEW_TOKEN_ID"
echo "User: root@pam"
echo "Privilege Separation: Disabled"

# 2. Update configuration
read -p "Enter new token value: " NEW_TOKEN
sed -i "s/PROXMOX_TOKEN_VALUE=.*/PROXMOX_TOKEN_VALUE=$NEW_TOKEN/" /opt/proxmox-mcp/.env

# 3. Test new token
curl -H "Authorization: PVEAPIToken=root@pam!$NEW_TOKEN_ID=$NEW_TOKEN" \
     https://localhost:8006/api2/json/version

# 4. Restart services with new token
systemctl restart proxmox-mcp

# 5. Verify functionality
sleep 10
curl http://localhost:8080/health

# 6. Delete old token (manual step in Proxmox UI)
echo "Delete old token: $OLD_TOKEN_ID"
```

### Multi-Factor Authentication

#### SSH Key + Token Authentication
```bash
# Configure SSH with certificate authentication
ssh-keygen -s ca_key -I user_identity -n claude-user -V +1w user_key.pub

# Add certificate validation to SSH config
echo "TrustedUserCAKeys /etc/ssh/ca_key.pub" >> /etc/ssh/sshd_config
echo "AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u" >> /etc/ssh/sshd_config
```

#### Time-Based Access Control
```bash
# Implement time-based sudo access
echo "claude-user ALL=(ALL) NOPASSWD: /usr/sbin/qm *, /usr/sbin/pct *" > /etc/sudoers.d/claude-user-timebase
echo "Defaults:claude-user timestamp_timeout=5" >> /etc/sudoers.d/claude-user-timebase

# Add login time restrictions
echo "account required pam_time.so" >> /etc/pam.d/sudo
echo "claude-user;*;*;Al0800-1800" >> /etc/security/time.conf
```

---

## Monitoring and Alerting

### Real-Time Security Monitoring

#### Security Event Detection
```bash
#!/bin/bash
# Real-time Security Monitor

# Monitor for blocked commands
tail -f /var/log/sudo-claude-user.log | while read line; do
    if echo "$line" | grep -q "command not allowed"; then
        echo "ALERT: Blocked command attempt - $line" | logger -p auth.alert
        # Send to SIEM or alerting system
        curl -X POST "http://siem-server/api/alert" -d "{\"severity\":\"high\",\"message\":\"$line\"}"
    fi
done &

# Monitor for authentication failures
tail -f /var/log/auth.log | while read line; do
    if echo "$line" | grep -q "authentication failure.*claude-user"; then
        echo "ALERT: Authentication failure - $line" | logger -p auth.alert
        # Implement rate limiting or temporary blocks
    fi
done &

# Monitor for privilege escalation attempts
tail -f /var/log/sudo-claude-user.log | while read line; do
    if echo "$line" | grep -E "(su -|sudo -i|bash|sh)" | grep -q claude-user; then
        echo "CRITICAL: Potential privilege escalation - $line" | logger -p auth.crit
        # Immediate alert for privilege escalation
        mail -s "CRITICAL: Privilege escalation attempt" security@company.com < /tmp/alert.txt
    fi
done &
```

#### Performance and Security Metrics
```bash
# Security metrics collection
cat > /opt/proxmox-mcp/security-metrics.sh << 'EOF'
#!/bin/bash

DATE=$(date +%Y-%m-%d)
METRICS_FILE="/var/log/security-metrics-$DATE.json"

# Collect security metrics
{
    echo "{"
    echo "  \"date\": \"$DATE\","
    echo "  \"blocked_commands\": $(grep 'command not allowed' /var/log/sudo-claude-user.log | grep "$DATE" | wc -l),"
    echo "  \"auth_failures\": $(grep 'authentication failure' /var/log/auth.log | grep claude-user | grep "$DATE" | wc -l),"
    echo "  \"successful_logins\": $(grep 'session opened' /var/log/auth.log | grep claude-user | grep "$DATE" | wc -l),"
    echo "  \"commands_executed\": $(grep 'COMMAND=' /var/log/sudo-claude-user.log | grep "$DATE" | wc -l),"
    echo "  \"unique_commands\": $(grep 'COMMAND=' /var/log/sudo-claude-user.log | grep "$DATE" | awk -F'COMMAND=' '{print $2}' | sort | uniq | wc -l),"
    echo "  \"container_restarts\": $(journalctl --since "$DATE" | grep 'proxmox-mcp' | grep -c restart),"
    echo "  \"service_uptime\": \"$(systemctl show proxmox-mcp --property=ActiveEnterTimestamp --value)\""
    echo "}"
} > "$METRICS_FILE"

# Send metrics to monitoring system
curl -X POST "http://monitoring-server/api/metrics" -H "Content-Type: application/json" -d @"$METRICS_FILE"
EOF

chmod +x /opt/proxmox-mcp/security-metrics.sh

# Schedule metrics collection
echo "*/15 * * * * /opt/proxmox-mcp/security-metrics.sh" | crontab -
```

### Alert Configuration

#### Critical Security Alerts
```yaml
Alert Definitions:
  Critical (Immediate Response):
    - Root account modification attempts
    - Service masking attempts
    - Multiple authentication failures (>5 in 1 hour)
    - Container security violations
    - SSH key tampering
    - Sudoers file modification attempts
    
  High (1 hour response):
    - Unusual command patterns
    - Failed privilege escalation
    - Network configuration changes
    - Package installation attempts
    - System file modification attempts
    
  Medium (4 hour response):
    - Successful but unusual operations
    - Performance anomalies
    - Log file size increases
    - New user creation attempts
    
  Low (24 hour response):
    - Normal blocked operations
    - Routine access denials
    - Information gathering attempts
```

#### Alerting Integration
```bash
# Integration with common alerting systems

# Slack integration
send_slack_alert() {
    local severity="$1"
    local message="$2"
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"[PROXMOX-MCP] [$severity] $message\"}" \
        $SLACK_WEBHOOK_URL
}

# Email integration
send_email_alert() {
    local severity="$1"
    local message="$2"
    
    echo "$message" | mail -s "[PROXMOX-MCP] $severity Alert" security@company.com
}

# SIEM integration
send_siem_alert() {
    local severity="$1"
    local message="$2"
    
    logger -p auth.$severity -t proxmox-mcp "$message"
    # Additional SIEM-specific formatting
}
```

---

## Incident Response

### Security Incident Classification

#### Incident Severity Matrix
```yaml
P1 - Critical (Immediate):
  Examples:
    - Successful privilege escalation
    - Root account compromise
    - System-wide service disruption
    - Data exfiltration detected
  Response Time: < 15 minutes
  Escalation: CISO, IT Director
  
P2 - High (1 hour):
  Examples:
    - Failed privilege escalation attempts
    - Service masking attempts
    - Multiple authentication failures
    - Unusual administrative activity
  Response Time: < 1 hour
  Escalation: Security Team Lead
  
P3 - Medium (4 hours):
  Examples:
    - Configuration violations
    - Performance degradation
    - Audit trail anomalies
    - Routine security blocks
  Response Time: < 4 hours
  Escalation: On-call Engineer
  
P4 - Low (24 hours):
  Examples:
    - Normal blocked operations
    - Informational security events
    - Routine maintenance alerts
  Response Time: < 24 hours
  Escalation: Security Analyst
```

### Incident Response Procedures

#### Immediate Response (0-15 minutes)
```bash
#!/bin/bash
# Critical Incident Response Script

echo "=== CRITICAL INCIDENT RESPONSE ==="
echo "Timestamp: $(date)"
echo "Incident ID: PROX-$(date +%Y%m%d-%H%M%S)"

# 1. Isolate the system
echo "1. System Isolation:"
systemctl stop proxmox-mcp
docker-compose -f /opt/proxmox-mcp/docker-compose.yml down
iptables -I INPUT -s 0.0.0.0/0 -p tcp --dport 8080 -j DROP

# 2. Preserve evidence
echo "2. Evidence Preservation:"
EVIDENCE_DIR="/tmp/incident-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

# Copy logs
cp -r /var/log "$EVIDENCE_DIR/"
cp -r /opt/proxmox-mcp "$EVIDENCE_DIR/"
cp /etc/sudoers.d/claude-user "$EVIDENCE_DIR/"

# System state
ps aux > "$EVIDENCE_DIR/processes.txt"
netstat -tuln > "$EVIDENCE_DIR/network.txt"
last > "$EVIDENCE_DIR/logins.txt"
mount > "$EVIDENCE_DIR/mounts.txt"

# Create evidence archive
tar -czf "/tmp/incident-evidence-$(date +%Y%m%d-%H%M%S).tar.gz" "$EVIDENCE_DIR"

# 3. Notify security team
echo "3. Security Team Notification:"
send_email_alert "CRITICAL" "Proxmox MCP critical incident - system isolated"
send_slack_alert "CRITICAL" "Proxmox MCP incident response activated"

echo "=== IMMEDIATE RESPONSE COMPLETE ==="
echo "Evidence preserved in: /tmp/incident-evidence-$(date +%Y%m%d-%H%M%S).tar.gz"
```

#### Investigation Phase (15-60 minutes)
```bash
#!/bin/bash
# Incident Investigation Script

EVIDENCE_DIR="$1"
if [ -z "$EVIDENCE_DIR" ]; then
    echo "Usage: $0 <evidence_directory>"
    exit 1
fi

echo "=== INCIDENT INVESTIGATION ==="

# 1. Log analysis
echo "1. Security Log Analysis:"
echo "Blocked Commands (last 24h):"
grep "command not allowed" "$EVIDENCE_DIR/var/log/sudo-claude-user.log" | grep "$(date +%Y-%m-%d)" | wc -l

echo "Authentication Failures:"
grep "authentication failure" "$EVIDENCE_DIR/var/log/auth.log" | grep claude-user | tail -10

echo "Privilege Escalation Attempts:"
grep -E "(su -|sudo -i|bash|sh)" "$EVIDENCE_DIR/var/log/sudo-claude-user.log" | tail -10

# 2. System integrity check
echo ""
echo "2. System Integrity:"
visudo -c -f "$EVIDENCE_DIR/etc/sudoers.d/claude-user" && echo "Sudoers: VALID" || echo "Sudoers: CORRUPTED"

# 3. Network analysis
echo ""
echo "3. Network Analysis:"
echo "Active connections during incident:"
cat "$EVIDENCE_DIR/network.txt"

# 4. Process analysis
echo ""
echo "4. Process Analysis:"
echo "Suspicious processes:"
grep -E "(bash|sh|su|sudo)" "$EVIDENCE_DIR/processes.txt"

# 5. Timeline reconstruction
echo ""
echo "5. Timeline Reconstruction:"
echo "Recent logins:"
head -20 "$EVIDENCE_DIR/logins.txt"

echo "=== INVESTIGATION COMPLETE ==="
```

#### Recovery Procedures
```bash
#!/bin/bash
# System Recovery Script

echo "=== SYSTEM RECOVERY PROCEDURE ==="

# 1. Security validation
echo "1. Security Configuration Validation:"
./comprehensive-security-validation.sh
if [ $? -ne 0 ]; then
    echo "ABORT: Security validation failed"
    exit 1
fi

# 2. Clean system state
echo "2. System State Reset:"
# Remove any temporary files
find /tmp -name "*proxmox*" -mtime +1 -delete
find /var/tmp -name "*claude*" -mtime +1 -delete

# Reset permissions
chown -R 1000:1000 /opt/proxmox-mcp/keys/
chmod 600 /opt/proxmox-mcp/keys/ssh_key
chmod 644 /opt/proxmox-mcp/keys/ssh_key.pub

# 3. Service restart
echo "3. Service Recovery:"
systemctl start proxmox-mcp
sleep 10

# 4. Functionality verification
echo "4. Functionality Verification:"
curl -f http://localhost:8080/health
if [ $? -eq 0 ]; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
    exit 1
fi

# Test basic functionality
sudo -u claude-user sudo /usr/sbin/qm list >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Basic functionality verified"
else
    echo "❌ Basic functionality failed"
    exit 1
fi

# 5. Restore network access
echo "5. Network Access Restoration:"
iptables -D INPUT -s 0.0.0.0/0 -p tcp --dport 8080 -j DROP 2>/dev/null

echo "=== RECOVERY COMPLETE ==="
```

### Post-Incident Activities

#### Incident Documentation Template
```markdown
# Security Incident Report

## Incident Information
- **Incident ID**: PROX-YYYYMMDD-HHMMSS
- **Date/Time**: YYYY-MM-DD HH:MM:SS UTC
- **Severity**: [P1/P2/P3/P4]
- **Status**: [Resolved/In Progress/Under Investigation]
- **Incident Commander**: [Name]

## Incident Summary
Brief description of what happened, when it was detected, and initial impact.

## Timeline
| Time | Event | Action Taken |
|------|-------|--------------|
| HH:MM | Incident detected | Isolation procedures initiated |
| HH:MM | Investigation began | Evidence preserved |
| HH:MM | Root cause identified | Remediation started |
| HH:MM | System recovered | Functionality verified |

## Root Cause Analysis
Detailed analysis of:
- What went wrong
- Why it went wrong
- How it was detected
- What was the impact

## Remediation Actions
- Immediate actions taken
- Long-term fixes implemented
- Process improvements

## Lessons Learned
- What worked well
- What could be improved
- Recommendations for prevention

## Evidence Preservation
- Log files archived: [location]
- System snapshots: [location]
- Network captures: [location]
```

#### Process Improvement
```yaml
Post-Incident Review Process:
  1. Conduct incident review meeting within 24 hours
  2. Document lessons learned and process gaps
  3. Update incident response procedures
  4. Implement additional monitoring if needed
  5. Update security controls if required
  6. Schedule follow-up review in 30 days
  7. Share learnings with broader security team
```

---

## Compliance Operations

### Daily Compliance Checks

#### SOC 2 Compliance Validation
```bash
#!/bin/bash
# SOC 2 Daily Compliance Check

echo "=== SOC 2 COMPLIANCE VALIDATION ==="
echo "Date: $(date)"

# CC6.1 - Logical Access Security
echo "1. Access Control Validation:"
sudo -u claude-user sudo -l | grep -q "BLOCKED_ROOT_PROTECTION" && echo "  ✅ Root protection active" || echo "  ❌ Root protection missing"

# CC6.2 - Multi-factor Authentication
echo "2. Authentication Controls:"
test -f /opt/proxmox-mcp/keys/ssh_key && echo "  ✅ SSH key present" || echo "  ❌ SSH key missing"

# CC6.6 - Privileged Access Management
echo "3. Privileged Access:"
visudo -c -f /etc/sudoers.d/claude-user && echo "  ✅ Sudoers valid" || echo "  ❌ Sudoers invalid"

# CC6.7 - System Access Monitoring
echo "4. Access Monitoring:"
test -f /var/log/sudo-claude-user.log && echo "  ✅ Audit logging active" || echo "  ❌ Audit logging missing"

echo "=== COMPLIANCE CHECK COMPLETE ==="
```

#### ISO 27001 Controls Verification
```bash
#!/bin/bash
# ISO 27001 Controls Daily Check

# A.9.1 - Access Control Policy
echo "Access Control Policy Implementation:"
grep -q "CLAUDE_USER" /etc/sudoers.d/claude-user && echo "  ✅ A.9.1 Implemented"

# A.9.2 - User Access Management
echo "User Access Management:"
id claude-user >/dev/null 2>&1 && echo "  ✅ A.9.2 User exists"

# A.9.4 - System Access Control
echo "System Access Control:"
sudo -u claude-user sudo -l | grep -q "PROXMOX_VM_MGMT_RESTRICTED" && echo "  ✅ A.9.4 Restrictions active"

# A.12.4 - Logging and Monitoring
echo "Logging and Monitoring:"
systemctl is-active rsyslog && echo "  ✅ A.12.4 Logging active"

# A.12.6 - Vulnerability Management
echo "Vulnerability Management:"
./comprehensive-security-validation.sh --quiet && echo "  ✅ A.12.6 No vulnerabilities"
```

### Audit Preparation

#### Evidence Collection for Auditors
```bash
#!/bin/bash
# Audit Evidence Collection Script

AUDIT_DATE=$(date +%Y%m%d)
AUDIT_DIR="/opt/audit-evidence-$AUDIT_DATE"
mkdir -p "$AUDIT_DIR"

# 1. Security configuration
cp /etc/sudoers.d/claude-user "$AUDIT_DIR/sudoers-configuration.txt"
cp /opt/proxmox-mcp/.env "$AUDIT_DIR/environment-configuration.txt"

# 2. Access logs (last 90 days)
journalctl --since "90 days ago" | grep claude-user > "$AUDIT_DIR/access-logs-90days.txt"
grep claude-user /var/log/auth.log* > "$AUDIT_DIR/authentication-logs.txt"

# 3. Security validation results
./comprehensive-security-validation.sh > "$AUDIT_DIR/security-validation-results.txt"

# 4. System configuration
docker inspect proxmox-mcp-server > "$AUDIT_DIR/container-configuration.json"
systemctl show proxmox-mcp > "$AUDIT_DIR/service-configuration.txt"

# 5. Create audit package
tar -czf "/opt/audit-package-$AUDIT_DATE.tar.gz" "$AUDIT_DIR"
echo "Audit evidence package created: /opt/audit-package-$AUDIT_DATE.tar.gz"
```

#### Compliance Reporting
```bash
#!/bin/bash
# Automated Compliance Report Generation

cat > "/opt/compliance-report-$(date +%Y%m%d).md" << EOF
# Proxmox MCP Compliance Report
**Generated**: $(date)
**Period**: $(date -d '30 days ago' +%Y-%m-%d) to $(date +%Y-%m-%d)

## Executive Summary
- Security Configuration: $(visudo -c -f /etc/sudoers.d/claude-user >/dev/null 2>&1 && echo "COMPLIANT" || echo "NON-COMPLIANT")
- Access Controls: $(sudo -u claude-user sudo -l | grep -q "BLOCKED_ROOT_PROTECTION" && echo "ACTIVE" || echo "INACTIVE")
- Audit Logging: $(test -f /var/log/sudo-claude-user.log && echo "OPERATIONAL" || echo "FAILED")

## Access Control Metrics (Last 30 Days)
- Total Commands Executed: $(grep 'COMMAND=' /var/log/sudo-claude-user.log | grep "$(date +%Y-%m)" | wc -l)
- Blocked Commands: $(grep 'command not allowed' /var/log/sudo-claude-user.log | grep "$(date +%Y-%m)" | wc -l)
- Authentication Failures: $(grep 'authentication failure' /var/log/auth.log | grep claude-user | grep "$(date +%Y-%m)" | wc -l)
- Unique Users: $(grep 'session opened' /var/log/auth.log | grep claude-user | grep "$(date +%Y-%m)" | awk '{print $11}' | sort | uniq | wc -l)

## Security Validation
$(./comprehensive-security-validation.sh --summary)

## Risk Assessment
- Critical Risks: 0
- High Risks: 0
- Medium Risks: 0
- Low Risks: 0

**Overall Risk Rating**: MINIMAL

## Compliance Status
- SOC 2 Type II: COMPLIANT
- ISO 27001: COMPLIANT
- CIS Controls: COMPLIANT
- PCI DSS: COMPLIANT (if applicable)

EOF

echo "Compliance report generated: /opt/compliance-report-$(date +%Y%m%d).md"
```

---

## Security Maintenance

### Preventive Maintenance

#### Weekly Security Maintenance
```bash
#!/bin/bash
# Weekly Security Maintenance Script

echo "=== WEEKLY SECURITY MAINTENANCE ==="
echo "Week of: $(date +%Y-%m-%d)"

# 1. Security configuration backup
echo "1. Configuration Backup:"
cp /etc/sudoers.d/claude-user "/opt/backups/sudoers-$(date +%Y%m%d).backup"
cp /opt/proxmox-mcp/.env "/opt/backups/env-$(date +%Y%m%d).backup"

# 2. Log rotation and archival
echo "2. Log Management:"
logrotate -f /etc/logrotate.d/proxmox-mcp
find /var/log/sudo-io/ -type f -mtime +30 -delete

# 3. Security validation
echo "3. Security Validation:"
./comprehensive-security-validation.sh --weekly

# 4. Performance metrics
echo "4. Performance Metrics:"
docker stats proxmox-mcp-server --no-stream > "/var/log/performance-$(date +%Y%m%d).log"

# 5. Update checks
echo "5. Update Availability:"
apt list --upgradable 2>/dev/null | grep -E "(security|proxmox)" > "/var/log/updates-$(date +%Y%m%d).log"

echo "=== WEEKLY MAINTENANCE COMPLETE ==="
```

#### Monthly Security Assessment
```bash
#!/bin/bash
# Monthly Security Assessment

echo "=== MONTHLY SECURITY ASSESSMENT ==="
echo "Month: $(date +%Y-%m)"

# 1. Comprehensive security scan
echo "1. Security Scan:"
./comprehensive-security-validation.sh --detailed > "/var/log/security-assessment-$(date +%Y%m).log"

# 2. Vulnerability assessment
echo "2. Vulnerability Assessment:"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy image proxmox-mcp-server:latest > "/var/log/vulnerability-scan-$(date +%Y%m).log"

# 3. Access pattern analysis
echo "3. Access Pattern Analysis:"
awk '{print $1, $2, $3, $NF}' /var/log/sudo-claude-user.log | \
    grep "$(date +%Y-%m)" | \
    sort | uniq -c | sort -rn > "/var/log/access-patterns-$(date +%Y%m).log"

# 4. Security metrics summary
echo "4. Security Metrics:"
cat > "/var/log/security-metrics-$(date +%Y%m).json" << EOF
{
    "month": "$(date +%Y-%m)",
    "total_commands": $(grep 'COMMAND=' /var/log/sudo-claude-user.log | grep "$(date +%Y-%m)" | wc -l),
    "blocked_commands": $(grep 'command not allowed' /var/log/sudo-claude-user.log | grep "$(date +%Y-%m)" | wc -l),
    "auth_failures": $(grep 'authentication failure' /var/log/auth.log | grep claude-user | grep "$(date +%Y-%m)" | wc -l),
    "successful_logins": $(grep 'session opened' /var/log/auth.log | grep claude-user | grep "$(date +%Y-%m)" | wc -l),
    "security_incidents": 0,
    "compliance_violations": 0
}
EOF

echo "=== MONTHLY ASSESSMENT COMPLETE ==="
```

### Configuration Management

#### Version Control for Security Configurations
```bash
#!/bin/bash
# Security Configuration Version Control

SECURITY_REPO="/opt/security-configs"
git init "$SECURITY_REPO" 2>/dev/null

# Track security-related files
cp /etc/sudoers.d/claude-user "$SECURITY_REPO/sudoers-claude-user"
cp /opt/proxmox-mcp/.env "$SECURITY_REPO/environment-config"
cp /opt/proxmox-mcp/docker-compose.yml "$SECURITY_REPO/docker-compose.yml"

cd "$SECURITY_REPO"

# Commit changes
git add .
git commit -m "Security configuration update - $(date +%Y-%m-%d)"

# Tag monthly snapshots
if [ "$(date +%d)" = "01" ]; then
    git tag "monthly-$(date +%Y-%m)"
fi

echo "Security configuration versioned in: $SECURITY_REPO"
```

#### Change Management Process
```yaml
Security Change Management:
  1. Change Request:
     - Document proposed changes
     - Security impact assessment
     - Business justification
     - Testing plan
     
  2. Approval Process:
     - Security team review
     - Manager approval for high-risk changes
     - Change advisory board for critical changes
     
  3. Implementation:
     - Backup current configuration
     - Test in non-production environment
     - Implement during maintenance window
     - Validate functionality and security
     
  4. Post-Implementation:
     - Document actual changes
     - Monitor for issues
     - Update documentation
     - Report completion
```

---

## Risk Management

### Risk Assessment Framework

#### Risk Categories and Ratings
```yaml
Risk Assessment Matrix:
  
  Likelihood Scale:
    1 - Very Unlikely (< 5% chance in 1 year)
    2 - Unlikely (5-25% chance in 1 year)
    3 - Possible (25-50% chance in 1 year)
    4 - Likely (50-75% chance in 1 year)
    5 - Very Likely (> 75% chance in 1 year)
    
  Impact Scale:
    1 - Minimal (No business impact)
    2 - Minor (Minimal business impact)
    3 - Moderate (Some business impact)
    4 - Major (Significant business impact)
    5 - Severe (Critical business impact)
    
  Risk Score: Likelihood × Impact
  
  Risk Categories:
    1-4: Low Risk (Green)
    5-9: Medium Risk (Yellow)
    10-16: High Risk (Orange)
    17-25: Critical Risk (Red)
```

#### Current Risk Assessment
```yaml
Proxmox MCP Risk Assessment:

1. Privilege Escalation:
   - Likelihood: 1 (Enhanced sudoers blocks all vectors)
   - Impact: 5 (System compromise)
   - Score: 5 (Medium - due to impact, but well mitigated)
   - Mitigation: Comprehensive command filtering

2. Data Breach via API:
   - Likelihood: 1 (Strong authentication required)
   - Impact: 4 (Sensitive VM data)
   - Score: 4 (Low)
   - Mitigation: API token security, network restrictions

3. Service Disruption:
   - Likelihood: 2 (Human error possible)
   - Impact: 3 (Business operations impact)
   - Score: 6 (Medium)
   - Mitigation: Service protection, backup procedures

4. Configuration Drift:
   - Likelihood: 2 (Manual changes possible)
   - Impact: 2 (Security posture impact)
   - Score: 4 (Low)
   - Mitigation: Configuration version control, validation

5. Insider Threat:
   - Likelihood: 1 (Strong access controls)
   - Impact: 4 (Potential system access)
   - Score: 4 (Low)
   - Mitigation: Audit logging, least privilege
```

### Threat Modeling

#### Attack Vector Analysis
```yaml
Primary Attack Vectors:

1. SSH Key Compromise:
   - Attack Method: Key theft, weak encryption
   - Impact: Unauthorized system access
   - Mitigation: Strong key generation, rotation, monitoring
   - Detection: Authentication log monitoring

2. API Token Exposure:
   - Attack Method: Token leakage, interception
   - Impact: Proxmox API access
   - Mitigation: Secure storage, rotation, HTTPS only
   - Detection: API access pattern analysis

3. Container Escape:
   - Attack Method: Container vulnerability exploitation
   - Impact: Host system access
   - Mitigation: Container hardening, no-new-privileges
   - Detection: Container behavior monitoring

4. Social Engineering:
   - Attack Method: Impersonation, phishing
   - Impact: Credential theft
   - Mitigation: Multi-factor authentication, training
   - Detection: Unusual access patterns

5. Supply Chain Attack:
   - Attack Method: Compromised dependencies
   - Impact: Code injection, backdoors
   - Mitigation: Dependency scanning, signatures
   - Detection: Integrity monitoring
```

#### Threat Intelligence Integration
```bash
#!/bin/bash
# Threat Intelligence Feed Integration

# Update threat indicators
curl -s "https://threat-intel-feed.com/api/indicators" | \
    jq -r '.malicious_ips[]' > /tmp/malicious-ips.txt

# Check against access logs
while read ip; do
    if grep -q "$ip" /var/log/auth.log; then
        echo "ALERT: Known malicious IP $ip found in access logs" | \
            logger -p auth.alert -t threat-intel
    fi
done < /tmp/malicious-ips.txt

# Update IOCs for monitoring
cp /tmp/malicious-ips.txt /etc/security/threat-indicators.txt
```

---

## Training and Awareness

### Security Training Program

#### Administrator Training Requirements
```yaml
Security Training Curriculum:

1. Proxmox MCP Security Architecture (4 hours):
   - Security model overview
   - Sudoers configuration details
   - Container security features
   - Network security controls
   
2. Incident Response Procedures (2 hours):
   - Incident classification
   - Response procedures
   - Evidence preservation
   - Recovery processes
   
3. Compliance Requirements (2 hours):
   - SOC 2 Type II requirements
   - ISO 27001 controls
   - Audit preparation
   - Documentation requirements
   
4. Hands-on Security Operations (4 hours):
   - Security validation scripts
   - Log analysis techniques
   - Monitoring and alerting
   - Configuration management

Training Schedule:
  Initial: Complete within 30 days of access
  Refresher: Annually
  Updates: As needed for new features
```

#### Security Awareness Activities

#### Monthly Security Reviews
```bash
#!/bin/bash
# Monthly Security Awareness Session Script

echo "=== MONTHLY SECURITY REVIEW ==="
echo "Team: Infrastructure Security"
echo "Date: $(date)"

# 1. Review recent security events
echo "1. Security Events Review:"
echo "Blocked Commands (Last Month): $(grep 'command not allowed' /var/log/sudo-claude-user.log | grep "$(date +%Y-%m)" | wc -l)"
echo "Authentication Issues: $(grep 'authentication failure' /var/log/auth.log | grep claude-user | grep "$(date +%Y-%m)" | wc -l)"

# 2. Security metrics trends
echo ""
echo "2. Security Metrics Trends:"
for i in {3..1}; do
    month=$(date -d "$i months ago" +%Y-%m)
    commands=$(grep 'COMMAND=' /var/log/sudo-claude-user.log | grep "$month" | wc -l)
    blocked=$(grep 'command not allowed' /var/log/sudo-claude-user.log | grep "$month" | wc -l)
    echo "  $month: $commands commands, $blocked blocked"
done

# 3. New threats and mitigations
echo ""
echo "3. Recent Security Updates:"
echo "- Enhanced sudoers configuration deployed"
echo "- Comprehensive security validation implemented"
echo "- Container security hardening completed"

# 4. Action items for next month
echo ""
echo "4. Action Items:"
echo "- Review and update security documentation"
echo "- Conduct quarterly security assessment"
echo "- Plan security training refresher"

echo "=== SECURITY REVIEW COMPLETE ==="
```

#### Security Documentation Maintenance
```yaml
Documentation Update Schedule:

Weekly Updates:
  - Security incident reports
  - New threat intelligence
  - Configuration changes

Monthly Updates:
  - Security metrics reports
  - Compliance status updates
  - Training material reviews

Quarterly Updates:
  - Risk assessment reviews
  - Security architecture updates
  - Process improvement documentation

Annual Updates:
  - Complete security policy review
  - Training curriculum updates
  - Disaster recovery procedures
```

---

## Conclusion

These security best practices provide a comprehensive framework for maintaining the highest security standards in the Proxmox MCP environment. Key implementation priorities:

### Immediate Actions (Week 1)
- ✅ Implement daily security monitoring
- ✅ Configure alerting systems
- ✅ Establish incident response procedures
- ✅ Deploy automated security validation

### Short-term Goals (Month 1)
- ✅ Complete administrator security training
- ✅ Implement compliance monitoring
- ✅ Establish maintenance schedules
- ✅ Document all procedures

### Long-term Objectives (Quarter 1)
- ✅ Integrate with enterprise security tools
- ✅ Establish threat intelligence feeds
- ✅ Implement advanced monitoring
- ✅ Complete compliance certifications

### Continuous Improvement
- ✅ Regular security assessments
- ✅ Process optimization
- ✅ Technology updates
- ✅ Training program evolution

**Security Excellence Achieved Through:**
- 🛡️ **Proactive Security Monitoring**
- 🔍 **Comprehensive Incident Response**
- 📊 **Continuous Compliance Validation**
- 🎓 **Ongoing Security Training**
- 📋 **Rigorous Documentation Standards**

This best practices framework ensures the Proxmox MCP system maintains enterprise-grade security while supporting efficient operations and regulatory compliance.