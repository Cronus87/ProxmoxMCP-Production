#!/usr/bin/env python3
"""
HTTP-based Proxmox MCP Server for remote access from any project
Built with FastMCP + FastAPI for production deployment
"""

import asyncio
import json
import os
import sys
import logging
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastmcp import FastMCP
import uvicorn
from typing import Optional, Dict, Any

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
async def lifespan(app: FastAPI):
    """FastAPI lifespan for proper MCP session management"""
    logger.info("🚀 Starting Proxmox MCP HTTP Server...")
    yield
    logger.info("🔌 Shutting down Proxmox MCP HTTP Server...")

# Setup environment first
setup_environment()

# Import Proxmox components after path setup
try:
    from environment_manager import EnvironmentManager
    from proxmox_mcp_server import ProxmoxMCPServer
    logger.info("✅ Proxmox components imported successfully")
except ImportError as e:
    logger.error(f"❌ Failed to import Proxmox components: {e}")
    sys.exit(1)

# Create FastMCP server
mcp = FastMCP("Proxmox MCP Server")

# Initialize Proxmox backend
env_manager = EnvironmentManager()
proxmox_backend = None

try:
    proxmox_backend = ProxmoxMCPServer()
    logger.info("✅ Proxmox backend initialized")
except Exception as e:
    logger.error(f"❌ Failed to initialize Proxmox backend: {e}")
    sys.exit(1)

# ==============================================================================
# MCP Tools Implementation
# ==============================================================================

@mcp.tool()
async def execute_command(command: str, timeout: int = 30) -> dict:
    """Execute a shell command on the Proxmox host via SSH"""
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
# FastAPI Application Setup
# ==============================================================================

# Create the MCP application
mcp_app = mcp.http_app(path="/mcp")

# Create main FastAPI application with lifespan
app = FastAPI(
    title="Proxmox MCP Server",
    description="HTTP-based MCP server for Proxmox VE management",
    version="1.0.0",
    lifespan=mcp_app.lifespan  # Essential for proper MCP session management
)

# Mount MCP server
app.mount("/api", mcp_app)

# Health check endpoint
@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring"""
    try:
        checks = {
            "mcp_backend": proxmox_backend is not None,
            "environment": env_manager.environment_type,  # Fixed: use property instead of method
            "config_loaded": True
        }
        
        # Test basic functionality if backend available
        if proxmox_backend:
            try:
                # Test if we can access the configuration
                ssh_enabled = proxmox_backend.config.get("enable_ssh", False)
                api_enabled = proxmox_backend.config.get("enable_proxmox_api", False)
                checks["ssh_enabled"] = ssh_enabled
                checks["api_enabled"] = api_enabled
                checks["proxmox_backend_config"] = True
            except Exception as e:
                logger.warning(f"Backend config check failed: {e}")
                checks["proxmox_backend_config"] = False
        
        # Determine overall status
        critical_checks = ["mcp_backend", "config_loaded"]
        status = "healthy" if all(checks.get(check, False) for check in critical_checks) else "degraded"
        
        return {
            "status": status,
            "checks": checks,
            "server": "Proxmox MCP HTTP Server",
            "version": "1.0.0"
        }
    except Exception as e:
        logger.error(f"Health check error: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }

# Root endpoint
@app.get("/")
async def root():
    """Root endpoint with server information"""
    return {
        "server": "Proxmox MCP HTTP Server",
        "version": "1.0.0",
        "mcp_endpoint": "/api/mcp",
        "health_endpoint": "/health",
        "docs": "/docs"
    }

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Proxmox MCP HTTP Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8080, help="Port to bind to")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload for development")
    args = parser.parse_args()
    
    logger.info(f"🌐 Starting Proxmox MCP HTTP Server on {args.host}:{args.port}")
    logger.info(f"📡 MCP endpoint: http://{args.host}:{args.port}/api/mcp")
    logger.info(f"🏥 Health check: http://{args.host}:{args.port}/health")
    logger.info(f"📚 API docs: http://{args.host}:{args.port}/docs")
    
    uvicorn.run(
        "main:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info"
    )

if __name__ == "__main__":
    main()