# Integration Guide

This section covers integrating Proxmox MCP with Claude Code and other enterprise systems.

## 🔌 Integration Options

| Integration Type | Guide | Use Case |
|------------------|-------|----------|
| **Claude Code** | [Claude Code Setup](claude-code-setup.md) | Primary MCP integration |
| **Direct API** | [API Integration](../reference/README.md) | Custom applications |
| **Enterprise SSO** | [Enterprise Integration](claude-code-setup.md#enterprise) | Corporate environments |

## 📚 Documentation in this Section

### [Claude Code Setup](claude-code-setup.md)
Complete guide for connecting Claude Code to Proxmox MCP, including basic setup, advanced configuration, and enterprise integration.

## 🚀 Quick Setup

### Basic Claude Code Connection
```bash
# Add MCP server
claude mcp add --transport http proxmox-production http://YOUR_IP:8080/api/mcp

# Verify connection
claude mcp list

# Test functionality
# Use Claude Code in any project to manage Proxmox
```

### API Access
```bash
# Health check
curl http://YOUR_IP:8080/health

# MCP endpoint
curl http://YOUR_IP:8080/api/mcp

# API documentation
curl http://YOUR_IP:8080/docs
```