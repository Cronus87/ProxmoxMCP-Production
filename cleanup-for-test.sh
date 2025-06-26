#!/bin/bash
# Complete cleanup script for end-to-end testing

echo "=== PROXMOX MCP COMPLETE CLEANUP ==="
echo "$(date): Starting complete system cleanup for testing"

# Stop and remove containers
echo "1. Stopping containers..."
cd /opt/proxmox-mcp/docker
docker-compose -f docker-compose.prod.yml down --volumes --remove-orphans 2>/dev/null || true

# Remove container images
echo "2. Removing container images..."
docker rmi proxmox-mcp-server:latest 2>/dev/null || true
docker system prune -f 2>/dev/null || true

# Remove all generated files (keep source code)
echo "3. Cleaning generated files..."
cd /opt/proxmox-mcp
rm -rf logs/ config/ backups/ 2>/dev/null || true
rm -f installation.log claude-mcp-config.json 2>/dev/null || true

# Remove SSH keys (will be regenerated)
echo "4. Removing SSH keys..."
rm -rf keys/ 2>/dev/null || true

# Remove environment file
echo "5. Removing environment files..."
rm -f docker/.env .env 2>/dev/null || true

# Remove claude-user (optional - comment out if you want to keep)
echo "6. Removing claude-user account..."
userdel -r claude-user 2>/dev/null || true
rm -f /etc/sudoers.d/claude-user* 2>/dev/null || true

# Clean Docker networks and volumes
echo "7. Cleaning Docker resources..."
docker network rm mcp-network 2>/dev/null || true
docker volume rm mcp_logs caddy_data caddy_config prometheus_data grafana_data 2>/dev/null || true

# Reset permissions
echo "8. Resetting permissions..."
chown -R root:root /opt/proxmox-mcp 2>/dev/null || true

echo "$(date): Cleanup completed - system ready for fresh installation"
echo "=== CLEANUP COMPLETE ==="