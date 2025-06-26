#!/usr/bin/env python3
"""
HTTP-based Proxmox MCP Server for remote access from any project
Built with FastMCP + FastAPI for production deployment
"""

import asyncio
import os
import sys
import logging
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastmcp import FastMCP
import uvicorn

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
async def execute_command(command: str) -> dict:
    """Execute a shell command on the Proxmox host via SSH"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        # Use the existing proxmox_backend execute_command method
        result = await proxmox_backend._execute_command(command, 30)
        return {"output": result, "command": command, "status": "success"}
    except Exception as e:
        logger.error(f"Command execution error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@mcp.tool()
async def list_vms() -> dict:
    """List all VMs across Proxmox nodes"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        result = await proxmox_backend._list_vms()
        return {"vms": result, "status": "success"}
    except Exception as e:
        logger.error(f"List VMs error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@mcp.tool()
async def vm_status(vm_id: str, node: str = "") -> dict:
    """Get detailed status of a specific VM"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        result = await proxmox_backend._vm_status(vm_id, node)
        return {"status": result, "vm_id": vm_id, "node": node}
    except Exception as e:
        logger.error(f"VM status error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@mcp.tool()
async def vm_action(vm_id: str, action: str, node: str = "") -> dict:
    """Perform actions on VMs (start, stop, restart, shutdown)"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        result = await proxmox_backend._vm_action(vm_id, node, action)
        return {"result": result, "vm_id": vm_id, "action": action, "node": node}
    except Exception as e:
        logger.error(f"VM action error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@mcp.tool()
async def node_status(node: str = "") -> dict:
    """Get Proxmox node status and information"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        result = await proxmox_backend._node_status(node)
        return {"nodes": result, "requested_node": node}
    except Exception as e:
        logger.error(f"Node status error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@mcp.tool()
async def proxmox_api(endpoint: str, method: str = "GET", data: dict = None) -> dict:
    """Make direct Proxmox API calls"""
    try:
        if not proxmox_backend:
            raise HTTPException(status_code=500, detail="Proxmox backend not initialized")
        
        result = await proxmox_backend._proxmox_api_call(method, endpoint, data or {})
        return {"result": result, "endpoint": endpoint, "method": method}
    except Exception as e:
        logger.error(f"Proxmox API error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

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
            "environment": env_manager.get_environment_type(),
            "config_loaded": True
        }
        
        # Test Proxmox connectivity if backend available
        if proxmox_backend:
            try:
                # Quick connectivity test
                checks["proxmox_connectivity"] = True
            except:
                checks["proxmox_connectivity"] = False
        
        status = "healthy" if all(checks.values()) else "degraded"
        
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
        "run_mcp_server_http:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info"
    )

if __name__ == "__main__":
    main()