# Reference Documentation

This section contains comprehensive technical reference documentation for Proxmox MCP.

## 📖 Technical Reference

| Reference Type | Document | Description |
|----------------|----------|-------------|
| **System Requirements** | [Requirements](requirements.md) | Hardware, software, and network requirements |
| **API Documentation** | [API Reference](../integration/claude-code-setup.md#api) | Complete MCP tool documentation |
| **Configuration** | [Configuration Reference](requirements.md#configuration) | All configuration options |
| **Architecture** | [System Architecture](requirements.md#architecture) | Technical architecture details |

## 📚 Documentation in this Section

### [Requirements](requirements.md)
Comprehensive system requirements, configuration options, and architecture documentation.

## 🔧 Quick Reference

### MCP Tools Available
- `execute_command(command, timeout)` - SSH command execution
- `list_vms()` - VM enumeration
- `vm_status(vmid, node)` - VM status
- `vm_action(vmid, node, action)` - VM lifecycle management
- `node_status(node)` - Node information
- `proxmox_api(method, path, data)` - Direct API access

### System Endpoints
- **MCP Server**: `http://SERVER_IP:8080/api/mcp`
- **Health Check**: `http://SERVER_IP:8080/health`
- **API Docs**: `http://SERVER_IP:8080/docs`