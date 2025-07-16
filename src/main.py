#!/usr/bin/env python3
"""
Dual-Port Proxmox MCP Server with Device Authentication
Port 8080: MCP endpoint with device token authentication
Port 8081: Admin interface for device management (local network only)
"""

import asyncio
import json
import os
import sys
import logging
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, Depends, status
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastmcp import FastMCP
import uvicorn
from typing import Optional, Dict, Any, List
import multiprocessing
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def setup_environment():
    """Setup environment and paths"""
    # Change to script directory for consistent paths
    script_dir = Path(__file__).parent
    os.chdir(script_dir)
    logger.info(f"Working directory: {script_dir}")
    
    # Add core to Python path
    core_path = script_dir / "core"
    sys.path.insert(0, str(core_path))
    
    # Load .env file
    try:
        from dotenv import load_dotenv
        env_path = script_dir / ".env"
        if env_path.exists():
            load_dotenv(env_path)
            logger.info(f"Loaded environment from: {env_path}")
        else:
            logger.warning(f"No .env file found at: {env_path}")
    except ImportError:
        logger.warning("python-dotenv not installed")

@asynccontextmanager
async def mcp_lifespan(app: FastAPI):
    """FastAPI lifespan for MCP server"""
    logger.info("🚀 Starting Proxmox MCP Server...")
    # Cleanup expired tokens on startup
    await device_auth_manager.cleanup_expired_tokens()
    yield
    logger.info("🔌 Shutting down Proxmox MCP Server...")

@asynccontextmanager
async def admin_lifespan(app: FastAPI):
    """FastAPI lifespan for admin server"""
    logger.info("🚀 Starting Proxmox MCP Admin Interface...")
    yield
    logger.info("🔌 Shutting down Proxmox MCP Admin Interface...")

# Setup environment first
setup_environment()

# Import components after path setup
try:
    from environment_manager import EnvironmentManager
    from proxmox_mcp_server import ProxmoxMCPServer
    from device_auth import DeviceAuthManager
    from security_middleware import SecurityMiddleware, SecurityMiddlewareFactory
    logger.info("✅ Proxmox components imported successfully")
except ImportError as e:
    logger.error(f"❌ Failed to import Proxmox components: {e}")
    sys.exit(1)

# Initialize core components
try:
    env_manager = EnvironmentManager()
    logger.info("✅ Environment manager initialized")
except Exception as e:
    logger.error(f"❌ Failed to initialize environment manager: {e}")
    sys.exit(1)

try:
    device_auth_manager = DeviceAuthManager()
    logger.info("✅ Device authentication manager initialized")
except Exception as e:
    logger.error(f"❌ Failed to initialize device authentication manager: {e}")
    sys.exit(1)

proxmox_backend = None
try:
    proxmox_backend = ProxmoxMCPServer()
    logger.info("✅ Proxmox backend initialized")
except Exception as e:
    logger.error(f"❌ Failed to initialize Proxmox backend: {e}")
    # This is not fatal - some functionality will be limited
    logger.warning("⚠️  Continuing without Proxmox backend - limited functionality available")

# Initialize security middleware
mcp_security = SecurityMiddlewareFactory.create_mcp_security(device_auth_manager)
admin_security = SecurityMiddlewareFactory.create_admin_security(device_auth_manager)

# Create FastMCP server
mcp = FastMCP("Proxmox MCP Server")

# ==============================================================================
# MCP Tools Implementation (with device authentication)
# ==============================================================================

@mcp.tool()
async def execute_command(command: str, timeout: int = 30) -> dict:
    """Execute a shell command on the Proxmox host via SSH (requires device authentication)"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        # Call the private method directly with proper parameters
        result = await proxmox_backend._execute_command(command, timeout)
        
        # Parse the JSON result to extract components
        try:
            result_data = json.loads(result) if isinstance(result, str) else result
            return {
                "command": command,
                "output": result_data.get("stdout", ""),
                "error": result_data.get("stderr", ""),
                "exit_status": result_data.get("exit_status", 0),
                "timestamp": result_data.get("timestamp", ""),
                "status": "success" if result_data.get("exit_status", 0) == 0 else "error"
            }
        except (json.JSONDecodeError, AttributeError):
            # Fallback for raw string results
            return {"output": str(result), "command": command, "status": "success"}
            
    except Exception as e:
        logger.error(f"Command execution error: {e}")
        return {
            "command": command,
            "output": "",
            "error": str(e),
            "exit_status": -1,
            "status": "error"
        }

@mcp.tool()
async def list_vms() -> dict:
    """List all VMs across Proxmox nodes"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        # Check if Proxmox API is enabled
        if not proxmox_backend.config.get("enable_proxmox_api", False):
            return {
                "vms": [],
                "status": "error",
                "error": "Proxmox API is disabled. Enable it in configuration to use this feature."
            }
        
        result = await proxmox_backend._list_vms()
        
        # Parse the JSON result
        try:
            vms_data = json.loads(result) if isinstance(result, str) else result
            return {"vms": vms_data, "status": "success"}
        except (json.JSONDecodeError, AttributeError):
            return {"vms": [], "status": "error", "error": "Failed to parse VM list"}
            
    except Exception as e:
        logger.error(f"List VMs error: {e}")
        return {"vms": [], "status": "error", "error": str(e)}

@mcp.tool()
async def vm_status(vmid: int, node: str) -> dict:
    """Get detailed status of a specific VM"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        # Check if Proxmox API is enabled
        if not proxmox_backend.config.get("enable_proxmox_api", False):
            return {
                "status": {},
                "vmid": vmid,
                "node": node,
                "error": "Proxmox API is disabled. Enable it in configuration to use this feature."
            }
        
        result = await proxmox_backend._vm_status(vmid, node)
        
        # Parse the JSON result
        try:
            status_data = json.loads(result) if isinstance(result, str) else result
            return {"status": status_data, "vmid": vmid, "node": node}
        except (json.JSONDecodeError, AttributeError):
            return {"status": {}, "vmid": vmid, "node": node, "error": "Failed to parse VM status"}
            
    except Exception as e:
        logger.error(f"VM status error: {e}")
        return {"status": {}, "vmid": vmid, "node": node, "error": str(e)}

@mcp.tool()
async def vm_action(vmid: int, node: str, action: str) -> dict:
    """Perform actions on VMs (start, stop, restart, shutdown)"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        # Check if Proxmox API is enabled
        if not proxmox_backend.config.get("enable_proxmox_api", False):
            return {
                "result": {},
                "vmid": vmid,
                "action": action,
                "node": node,
                "error": "Proxmox API is disabled. Enable it in configuration to use this feature."
            }
        
        # Validate action
        valid_actions = ["start", "stop", "restart", "shutdown", "suspend", "resume"]
        if action not in valid_actions:
            return {
                "result": {},
                "vmid": vmid,
                "action": action,
                "node": node,
                "error": f"Invalid action. Valid actions are: {', '.join(valid_actions)}"
            }
        
        result = await proxmox_backend._vm_action(vmid, node, action)
        
        # Parse the JSON result
        try:
            action_data = json.loads(result) if isinstance(result, str) else result
            return {"result": action_data, "vmid": vmid, "action": action, "node": node}
        except (json.JSONDecodeError, AttributeError):
            return {"result": {}, "vmid": vmid, "action": action, "node": node, "error": "Failed to parse action result"}
            
    except Exception as e:
        logger.error(f"VM action error: {e}")
        return {"result": {}, "vmid": vmid, "action": action, "node": node, "error": str(e)}

@mcp.tool()
async def node_status(node: Optional[str] = None) -> dict:
    """Get Proxmox node status and information"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        # Check if Proxmox API is enabled
        if not proxmox_backend.config.get("enable_proxmox_api", False):
            return {
                "nodes": [],
                "requested_node": node,
                "error": "Proxmox API is disabled. Enable it in configuration to use this feature."
            }
        
        result = await proxmox_backend._node_status(node)
        
        # Parse the JSON result
        try:
            nodes_data = json.loads(result) if isinstance(result, str) else result
            return {"nodes": nodes_data, "requested_node": node}
        except (json.JSONDecodeError, AttributeError):
            return {"nodes": [], "requested_node": node, "error": "Failed to parse node status"}
            
    except Exception as e:
        logger.error(f"Node status error: {e}")
        return {"nodes": [], "requested_node": node, "error": str(e)}

@mcp.tool()
async def proxmox_api(method: str, path: str, data: Optional[Dict[str, Any]] = None) -> dict:
    """Make direct Proxmox API calls"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        # Check if Proxmox API is enabled
        if not proxmox_backend.config.get("enable_proxmox_api", False):
            return {
                "result": {},
                "path": path,
                "method": method,
                "error": "Proxmox API is disabled. Enable it in configuration to use this feature."
            }
        
        # Validate method
        valid_methods = ["GET", "POST", "PUT", "DELETE"]
        if method.upper() not in valid_methods:
            return {
                "result": {},
                "path": path,
                "method": method,
                "error": f"Invalid method. Valid methods are: {', '.join(valid_methods)}"
            }
        
        result = await proxmox_backend._proxmox_api_call(method.upper(), path, data)
        
        # Parse the JSON result
        try:
            api_data = json.loads(result) if isinstance(result, str) else result
            return {"result": api_data, "path": path, "method": method}
        except (json.JSONDecodeError, AttributeError):
            return {"result": {}, "path": path, "method": method, "error": "Failed to parse API response"}
            
    except Exception as e:
        logger.error(f"Proxmox API error: {e}")
        return {"result": {}, "path": path, "method": method, "error": str(e)}

# ==============================================================================
# MCP FastAPI Application (Port 8080) - Requires Device Authentication
# ==============================================================================

# Create the authenticated MCP application
mcp_app = mcp.http_app(path="/mcp")

# Custom middleware for MCP app to require authentication
@mcp_app.middleware("http")
async def authenticate_mcp_requests(request: Request, call_next):
    """Middleware to authenticate all MCP requests"""
    try:
        # Skip authentication for health check
        if request.url.path in ["/health", "/register"]:
            return await call_next(request)
        
        # For MCP endpoints, require device authentication
        if request.url.path.startswith("/mcp"):
            device_info = await mcp_security.authenticate_device_token(request)
            request.state.device_info = device_info
        
        return await call_next(request)
    except HTTPException as e:
        return JSONResponse(
            status_code=e.status_code,
            content={"error": e.detail, "type": "authentication_error"}
        )
    except Exception as e:
        logger.error(f"Authentication middleware error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Authentication service error", "type": "internal_error"}
        )

# Create main MCP FastAPI application
mcp_server_app = FastAPI(
    title="Proxmox MCP Server",
    description="Authenticated MCP server for Proxmox VE management",
    version="2.0.0",
    lifespan=mcp_lifespan
)

# Mount MCP server
mcp_server_app.mount("/api", mcp_app)

# Device registration endpoint (unauthenticated)
@mcp_server_app.post("/register")
@mcp_security.rate_limit(max_requests=5, window_seconds=900)  # 5 requests per 15 minutes
async def register_device(request: Request):
    """Register a new device for MCP access"""
    try:
        # Get registration data from request body
        body = await request.json()
        device_name = body.get("device_name")
        client_info = body.get("client_info", "Unknown")
        
        if not device_name:
            raise HTTPException(status_code=400, detail="device_name is required")
        
        client_ip = mcp_security._get_client_ip(request)
        user_agent = request.headers.get("User-Agent", "Unknown")
        
        success, message, device_id = await device_auth_manager.request_device_registration(
            device_name=device_name,
            client_info=client_info,
            ip_address=client_ip,
            user_agent=user_agent
        )
        
        if success:
            return {
                "success": True,
                "message": message,
                "device_id": device_id,
                "next_steps": "Your registration request has been submitted. An administrator will review and approve your device. You will receive a token once approved."
            }
        else:
            raise HTTPException(status_code=400, detail=message)
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Device registration error: {e}")
        raise HTTPException(status_code=500, detail="Registration service error")

# Health check endpoint
@mcp_server_app.get("/health")
async def mcp_health_check():
    """Health check endpoint for MCP server"""
    try:
        checks = {
            "mcp_backend": proxmox_backend is not None,
            "environment": env_manager.environment_type,
            "device_auth": True,
            "config_loaded": True
        }
        
        # Test basic functionality
        if proxmox_backend:
            try:
                ssh_enabled = proxmox_backend.config.get("enable_ssh", False)
                api_enabled = proxmox_backend.config.get("enable_proxmox_api", False)
                checks["ssh_enabled"] = ssh_enabled
                checks["api_enabled"] = api_enabled
                checks["proxmox_backend_config"] = True
            except Exception as e:
                logger.warning(f"Backend config check failed: {e}")
                checks["proxmox_backend_config"] = False
        
        # Get auth stats
        try:
            stats = await device_auth_manager.get_system_stats()
            checks["device_stats"] = stats
        except Exception as e:
            logger.warning(f"Device stats check failed: {e}")
            checks["device_stats"] = {}
        
        # Determine overall status
        critical_checks = ["mcp_backend", "config_loaded", "device_auth"]
        status = "healthy" if all(checks.get(check, False) for check in critical_checks) else "degraded"
        
        return {
            "status": status,
            "checks": checks,
            "server": "Proxmox MCP Server (Authenticated)",
            "version": "2.0.0",
            "authentication": "required"
        }
    except Exception as e:
        logger.error(f"Health check error: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }

# Root endpoint
@mcp_server_app.get("/")
async def mcp_root():
    """Root endpoint with server information"""
    return {
        "server": "Proxmox MCP Server (Authenticated)",
        "version": "2.0.0",
        "authentication": "required",
        "mcp_endpoint": "/api/mcp",
        "register_endpoint": "/register",
        "health_endpoint": "/health",
        "docs": "/docs",
        "message": "This MCP server requires device authentication. Register your device first, then get approval from an administrator."
    }

# ==============================================================================
# Admin FastAPI Application (Port 8081) - Local Network Only
# ==============================================================================

# Setup templates
templates = Jinja2Templates(directory="templates")

# Create admin FastAPI application
admin_app = FastAPI(
    title="Proxmox MCP Admin Interface",
    description="Local network administration interface for device management",
    version="2.0.0",
    lifespan=admin_lifespan
)

# Local network restriction middleware
@admin_app.middleware("http")
async def restrict_to_local_network(request: Request, call_next):
    """Middleware to restrict access to local network only"""
    try:
        client_ip = admin_security._get_client_ip(request)
        
        # Allow local network access only
        if not admin_security._is_local_network(client_ip):
            logger.warning(f"Non-local access attempt to admin interface from {client_ip}")
            return JSONResponse(
                status_code=403,
                content={
                    "error": "Access Denied",
                    "detail": "Admin interface is restricted to local network access only",
                    "type": "network_restriction"
                }
            )
        
        return await call_next(request)
    except Exception as e:
        logger.error(f"Network restriction middleware error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Network security error", "type": "internal_error"}
        )

# Rate limiting for admin endpoints
@admin_app.middleware("http")
async def admin_rate_limiting(request: Request, call_next):
    """Rate limiting for admin endpoints"""
    try:
        client_ip = admin_security._get_client_ip(request)
        rate_key = f"admin:{client_ip}"
        
        # More generous rate limits for admin interface
        if not admin_security._check_rate_limit(rate_key, max_requests=120, window_seconds=60):
            return JSONResponse(
                status_code=429,
                content={
                    "error": "Rate Limit Exceeded",
                    "detail": "Too many requests. Please slow down.",
                    "type": "rate_limit_error"
                }
            )
        
        return await call_next(request)
    except Exception as e:
        logger.error(f"Rate limiting middleware error: {e}")
        return await call_next(request)

# Admin web interface routes
@admin_app.get("/", response_class=HTMLResponse)
async def admin_dashboard(request: Request):
    """Admin dashboard"""
    try:
        stats = await device_auth_manager.get_system_stats()
        return templates.TemplateResponse("dashboard.html", {
            "request": request,
            "active_page": "dashboard",
            "stats": stats
        })
    except Exception as e:
        logger.error(f"Dashboard error: {e}")
        return templates.TemplateResponse("dashboard.html", {
            "request": request,
            "active_page": "dashboard",
            "stats": {
                "active_devices": 0,
                "pending_requests": 0,
                "total_devices": 0,
                "revoked_devices": 0,
                "expired_devices": 0
            }
        })

@admin_app.get("/pending", response_class=HTMLResponse)
async def admin_pending(request: Request):
    """Pending requests page"""
    return templates.TemplateResponse("pending.html", {
        "request": request,
        "active_page": "pending"
    })

@admin_app.get("/devices", response_class=HTMLResponse)
async def admin_devices(request: Request):
    """Approved devices page"""
    return templates.TemplateResponse("devices.html", {
        "request": request,
        "active_page": "devices"
    })

# API endpoints for admin interface
@admin_app.get("/api/stats")
async def get_system_stats():
    """Get system statistics"""
    try:
        return await device_auth_manager.get_system_stats()
    except Exception as e:
        logger.error(f"Stats API error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get system statistics")

@admin_app.get("/api/pending")
async def get_pending_requests():
    """Get pending device requests"""
    try:
        return await device_auth_manager.get_pending_requests()
    except Exception as e:
        logger.error(f"Pending requests API error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get pending requests")

@admin_app.get("/api/devices")
async def get_approved_devices():
    """Get approved devices"""
    try:
        return await device_auth_manager.get_approved_devices()
    except Exception as e:
        logger.error(f"Approved devices API error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get approved devices")

@admin_app.post("/api/approve/{device_id}")
async def approve_device_request(device_id: str, request: Request):
    """Approve a device registration request"""
    try:
        # Get expiry_days from request body
        body = await request.json()
        expiry_days = body.get("expiry_days", 30)
        
        success, message, token = await device_auth_manager.approve_device(device_id, expiry_days)
        
        if success:
            return {
                "success": True,
                "message": message,
                "token": token,
                "device_name": message.split(":")[1].strip() if ":" in message else "Device"
            }
        else:
            raise HTTPException(status_code=400, detail=message)
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Device approval error: {e}")
        raise HTTPException(status_code=500, detail="Failed to approve device")

@admin_app.delete("/api/reject/{device_id}")
async def reject_device_request(device_id: str):
    """Reject a device registration request"""
    try:
        # Load and remove pending request
        pending_requests = await device_auth_manager._load_json_file(device_auth_manager.pending_requests_file)
        
        if device_id not in pending_requests:
            raise HTTPException(status_code=404, detail="Device request not found")
        
        device_name = pending_requests[device_id].get("device_name", "Unknown")
        del pending_requests[device_id]
        
        await device_auth_manager._save_json_file(device_auth_manager.pending_requests_file, pending_requests)
        
        logger.info(f"Device request rejected: {device_name} ({device_id})")
        return {"success": True, "message": f"Device request for {device_name} has been rejected"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Device rejection error: {e}")
        raise HTTPException(status_code=500, detail="Failed to reject device request")

@admin_app.post("/api/revoke/{device_id}")
async def revoke_device_access(device_id: str, request: Request):
    """Revoke device access"""
    try:
        # Get reason from request body
        body = await request.json()
        reason = body.get("reason", "Manual revocation")
        
        success, message = await device_auth_manager.revoke_device(device_id, reason)
        
        if success:
            return {"success": True, "message": message}
        else:
            raise HTTPException(status_code=400, detail=message)
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Device revocation error: {e}")
        raise HTTPException(status_code=500, detail="Failed to revoke device access")

# Admin health check
@admin_app.get("/health")
async def admin_health_check():
    """Health check for admin interface"""
    try:
        stats = await device_auth_manager.get_system_stats()
        return {
            "status": "healthy",
            "server": "Proxmox MCP Admin Interface",
            "version": "2.0.0",
            "network_restriction": "local_only",
            "device_stats": stats
        }
    except Exception as e:
        logger.error(f"Admin health check error: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }

def run_mcp_server():
    """Run MCP server on port 8080"""
    uvicorn.run(
        "main:mcp_server_app",
        host="0.0.0.0",
        port=8080,
        log_level="info",
        access_log=True
    )

def run_admin_server():
    """Run admin interface on port 8081 (local network only)"""
    uvicorn.run(
        "main:admin_app",
        host="0.0.0.0",  # Will be restricted by middleware
        port=8081,
        log_level="info",
        access_log=True
    )

def main():
    """Main entry point - runs both servers"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Proxmox MCP Dual-Port Server")
    parser.add_argument("--mode", choices=["mcp", "admin", "both"], default="both",
                       help="Run mode: mcp (port 8080), admin (port 8081), or both")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload for development")
    args = parser.parse_args()
    
    if args.mode == "mcp":
        logger.info("🌐 Starting MCP Server only on port 8080")
        logger.info("📡 MCP endpoint: http://0.0.0.0:8080/api/mcp")
        logger.info("🔐 Device registration: http://0.0.0.0:8080/register")
        logger.info("🏥 Health check: http://0.0.0.0:8080/health")
        
        if args.reload:
            uvicorn.run("main:mcp_server_app", host="0.0.0.0", port=8080, reload=True, log_level="info")
        else:
            run_mcp_server()
            
    elif args.mode == "admin":
        logger.info("🔧 Starting Admin Interface only on port 8081")
        logger.info("🖥️  Admin dashboard: http://localhost:8081/")
        logger.info("🏥 Health check: http://localhost:8081/health")
        
        if args.reload:
            uvicorn.run("main:admin_app", host="0.0.0.0", port=8081, reload=True, log_level="info")
        else:
            run_admin_server()
            
    else:  # both
        logger.info("🚀 Starting Dual-Port Proxmox MCP Server")
        logger.info("📡 MCP Server (Port 8080): http://0.0.0.0:8080/api/mcp")
        logger.info("🔐 Device Registration: http://0.0.0.0:8080/register")
        logger.info("🖥️  Admin Interface (Port 8081): http://localhost:8081/")
        logger.info("🏥 MCP Health: http://0.0.0.0:8080/health")
        logger.info("🏥 Admin Health: http://localhost:8081/health")
        logger.info("")
        logger.info("🔒 Security Features:")
        logger.info("   • Port 8080: Device token authentication required")
        logger.info("   • Port 8081: Local network access only")
        logger.info("   • Rate limiting on both ports")
        logger.info("   • Token expiration and revocation support")
        
        if args.reload:
            # For development, run both in threads
            import threading
            import time
            
            def run_mcp():
                uvicorn.run("main:mcp_server_app", host="0.0.0.0", port=8080, reload=False, log_level="info")
            
            def run_admin():
                uvicorn.run("main:admin_app", host="0.0.0.0", port=8081, reload=False, log_level="info")
            
            mcp_thread = threading.Thread(target=run_mcp, daemon=True)
            admin_thread = threading.Thread(target=run_admin, daemon=True)
            
            mcp_thread.start()
            time.sleep(1)  # Stagger startup
            admin_thread.start()
            
            try:
                mcp_thread.join()
            except KeyboardInterrupt:
                logger.info("Shutting down servers...")
        else:
            # Production: run both servers using multiprocessing
            mcp_process = multiprocessing.Process(target=run_mcp_server)
            admin_process = multiprocessing.Process(target=run_admin_server)
            
            try:
                mcp_process.start()
                admin_process.start()
                
                mcp_process.join()
                admin_process.join()
                
            except KeyboardInterrupt:
                logger.info("Shutting down servers...")
                mcp_process.terminate()
                admin_process.terminate()
                mcp_process.join()
                admin_process.join()

if __name__ == "__main__":
    main()