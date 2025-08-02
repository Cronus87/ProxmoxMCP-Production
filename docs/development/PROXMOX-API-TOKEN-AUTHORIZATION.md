# Proxmox API Token Authorization Implementation

## Overview
This document outlines the implementation plan for adding Proxmox API token authorization to the MCP server, enabling secure authentication through Claude Code's `--header` option.

## Current Status
**Research Complete** - Ready for implementation planning

## Key Findings

### Codebase Analysis
**Current Architecture:**
- Dual-port FastAPI application (8080: MCP, 8081: Admin)
- Uses FastMCP with HTTP transport for MCP protocol
- Device token authentication system in place
- Middleware-based authentication architecture
- Existing Proxmox API integration via `proxmoxer` library

**Key Components:**
- `/src/main.py`: Main server with authentication middleware (lines 325-349)
- `/src/core/security_middleware.py`: HTTPBearer token processing (lines 88-126)
- `/src/core/proxmox_mcp_server.py`: Proxmox API client integration
- Docker networking: Production ready with reverse proxy support

### Current Authentication Implementation
**Device Token Flow:**
1. HTTPBearer extracts `Authorization: Bearer <token>` headers
2. SecurityMiddleware validates token against device database
3. Device info stored in `request.state.device_info`
4. MCP tools access authenticated context

**Authentication Middleware Location:**
- `authenticate_mcp_requests()` in main.py (line 325)
- Uses `mcp_security.authenticate_device_token()` for validation
- Processes all `/mcp` endpoint requests

### MCP Server Configuration
**Network Setup:**
- **Endpoint**: `http://SERVER_IP:8080/api/mcp`
- **Docker Ports**: 8080 (MCP), 8081 (Admin)
- **Middleware Stack**: Rate limiting → Network restriction → Authentication → MCP processing
- **FastMCP Integration**: HTTP app mounted at `/api/mcp`

**Current Header Processing:**
- FastAPI `HTTPBearer` security scheme
- Direct header access via `request.headers.get('Authorization')`
- Request state management for authentication context

### Proxmox API Token Requirements
**Token Format:**
```
Authorization: PVEAPIToken=USER@REALM!TOKENID=UUID
```

**Examples:**
- `PVEAPIToken=root@pam!monitoring=aaaaaaaaa-bbb-cccc-dddd-ef0123456789`
- `PVEAPIToken=api@pam!claude-access=7ac4849f-19c1-4dcd-8fc7-6371e7e4xxxx`

**Token Characteristics:**
- Stateless authentication (no CSRF required)
- Permissions subset of corresponding user
- Direct REST API access without session management
- UUID-based secret values

## Implementation Plan

### Phase 1: Research & Analysis ✅
- [x] Analyze current authentication implementation
- [x] Review MCP server endpoint configuration
- [x] Research Proxmox API token authentication
- [x] Document current security model

### Phase 2: Design & Implementation
**Authentication Flow Design:**
1. **Dual Authentication Support**: Support both PVEAPIToken and Bearer token formats
2. **Header Detection**: Detect token format and route to appropriate authentication method
3. **Proxmox Token Validation**: Validate PVEAPIToken against Proxmox API directly
4. **Backward Compatibility**: Maintain existing device token authentication

**Implementation Approach:**
```python
# Modified authenticate_mcp_requests middleware
async def authenticate_mcp_requests(request: Request, call_next):
    auth_header = request.headers.get("Authorization", "")
    
    if auth_header.startswith("PVEAPIToken="):
        # Proxmox API Token authentication
        device_info = await authenticate_proxmox_token(request, auth_header)
    elif auth_header.startswith("Bearer "):
        # Existing device token authentication
        device_info = await mcp_security.authenticate_device_token(request)
    else:
        raise HTTPException(401, "Authentication required")
    
    request.state.device_info = device_info
    return await call_next(request)
```

**Key Changes Required:**
1. **SecurityMiddleware Enhancement**: Add `authenticate_proxmox_token()` method
2. **Token Validation**: Implement Proxmox API validation using existing proxmoxer client
3. **Configuration**: Add Proxmox host/settings for token validation
4. **Error Handling**: Proper error responses for invalid tokens

### Phase 3: Configuration & Integration
- [ ] Add environment variables for Proxmox validation endpoint
- [ ] Update security middleware with Proxmox token validation
- [ ] Modify main.py authentication middleware
- [ ] Add Proxmox token authentication to existing ProxmoxMCPServer class

### Phase 4: Testing & Documentation
- [ ] Create test scenarios for both authentication methods
- [ ] Validate security implementation
- [ ] Update setup guides with new authentication options
- [ ] Create troubleshooting documentation

## Setup Guide Steps

### Prerequisites
- Proxmox VE server with API access enabled
- Administrative access to create API tokens
- Claude Code CLI installed
- MCP server deployed and running

### Step 1: Generate Proxmox API Token
1. **Access Proxmox Web Interface** as administrator
2. **Navigate to Datacenter → Permissions → API Tokens**
3. **Create New API Token:**
   - **User**: Select existing user (e.g., `root@pam`) or create dedicated user
   - **Token ID**: Choose descriptive name (e.g., `claude-access`)
   - **Privilege Separation**: Recommended to enable for security
   - **Expiration**: Set appropriate expiration date
4. **Set Permissions**: Assign necessary permissions to the token user:
   - **VM.Audit**: View VM configurations and status
   - **VM.PowerMgmt**: Start/stop/restart VMs
   - **VM.Console**: Access VM console (if needed)
   - **Sys.Audit**: View system information
   - **Datastore.Audit**: View storage information
5. **Record Token Details**: Save the token in format:
   ```
   USER@REALM!TOKENID=UUID
   # Example: root@pam!claude-access=a1b2c3d4-5678-90ab-cdef-123456789abc
   ```

### Step 2: Configure MCP Server (Optional)
The MCP server will automatically validate Proxmox tokens against your Proxmox host. You may optionally configure validation settings in the environment:

**.env Configuration:**
```bash
# Proxmox Token Validation (Optional - uses runtime validation)
PROXMOX_VALIDATION_HOST=192.168.1.137  # Your Proxmox host IP
PROXMOX_VALIDATION_PORT=8006           # Default Proxmox API port
PROXMOX_VERIFY_SSL=false              # Set to true for production
```

### Step 3: Connect Claude Code with Proxmox Token
```bash
# Add MCP server with Proxmox API token authentication
claude mcp add --transport http proxmox-production http://your-server:8080/api/mcp --header "Authorization: PVEAPIToken=root@pam!claude-access=a1b2c3d4-5678-90ab-cdef-123456789abc"

# Verify connection
claude mcp list

# Test functionality
claude mcp run proxmox-production list_vms
```

### Step 4: Verify Connection and Permissions
1. **Test VM Listing:**
   ```bash
   claude mcp run proxmox-production list_vms
   ```

2. **Test Node Status:**
   ```bash
   claude mcp run proxmox-production node_status
   ```

3. **Test VM Operations** (if permitted):
   ```bash
   claude mcp run proxmox-production vm_status --vmid 100 --node pve
   ```

### Alternative: Hybrid Authentication
The system supports both authentication methods simultaneously:

```bash
# Proxmox API Token (recommended for production)
claude mcp add --transport http proxmox-prod http://server:8080/api/mcp --header "Authorization: PVEAPIToken=root@pam!token=uuid"

# Device Token (existing method)
claude mcp add --transport http proxmox-dev http://server:8080/api/mcp --header "Authorization: Bearer device-token-here"
```

## Security Considerations

### Token Security Best Practices
- **Principle of Least Privilege**: Grant only necessary permissions to API tokens
- **Token Expiration**: Set reasonable expiration dates and rotate tokens regularly
- **Secure Storage**: Store tokens securely in Claude Code configuration
- **Network Security**: Use HTTPS in production environments
- **Monitoring**: Enable audit logging for API token usage

### Token Validation Process
1. **Format Validation**: Verify PVEAPIToken format structure
2. **API Validation**: Test token against Proxmox API `/version` endpoint
3. **Permission Checking**: Validate token has required permissions for requested operations
4. **Rate Limiting**: Apply rate limits to prevent abuse
5. **Audit Logging**: Log all authentication attempts and API calls

### Security Implications
- **Stateless Authentication**: No session management required
- **Direct API Access**: Bypasses device registration process
- **Permission Inheritance**: Token permissions are subset of user permissions
- **Revocation**: Tokens can be revoked instantly from Proxmox interface

## Production Deployment Checklist

### Before Deployment
- [ ] Create dedicated Proxmox user for API access
- [ ] Generate API token with appropriate permissions
- [ ] Configure SSL/TLS for MCP server
- [ ] Set up monitoring and logging
- [ ] Test token validation and revocation

### After Deployment
- [ ] Verify Claude Code connection with API token
- [ ] Test all MCP tools with new authentication
- [ ] Monitor logs for authentication errors
- [ ] Document token management procedures
- [ ] Set up token rotation schedule

---
*Document updated: 2025-08-02*
*Status: Implementation ready*