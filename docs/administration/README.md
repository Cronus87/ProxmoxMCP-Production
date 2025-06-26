# Administration Guide

This section provides comprehensive guidance for administrators managing Proxmox MCP in production environments.

## 📋 Daily Operations

| Task | Guide | Frequency |
|------|-------|-----------|
| **Health Monitoring** | [Daily Operations](daily-operations.md) | Daily |
| **Security Validation** | [Security Best Practices](../security/best-practices.md) | Weekly |
| **System Updates** | [Maintenance Procedures](daily-operations.md#updates) | Monthly |
| **Backup Verification** | [Backup & Recovery](daily-operations.md#backup) | Weekly |

## 📚 Documentation in this Section

### [Daily Operations](daily-operations.md)
Comprehensive guide for routine administration tasks including monitoring, maintenance, updates, and backup procedures.

### [Troubleshooting](troubleshooting.md)
Complete troubleshooting guide with solutions for common issues, diagnostic procedures, and escalation paths.

## 🔧 Quick Reference

### Health Check Commands
```bash
# Check service status
curl http://localhost:8080/health

# View container logs
cd /opt/proxmox-mcp/docker && docker-compose logs -f

# Monitor resource usage
docker stats proxmox-mcp-server
```

### Emergency Procedures
```bash
# Restart services
cd /opt/proxmox-mcp/docker && docker-compose restart

# Full container recreation
cd /opt/proxmox-mcp/docker && docker-compose down && docker-compose up -d

# Check security status
sudo ./scripts/security/comprehensive-security-validation.sh
```