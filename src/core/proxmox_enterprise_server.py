#!/usr/bin/env python3
"""
Proxmox Enterprise MCP Server - Enhanced Multi-Node Management
Self-contained testing environment with enhanced security and container creation
"""

import asyncio
import json
import logging
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime

# Add parent directory to path to import base server
sys.path.append(str(Path(__file__).parent.parent.parent))
from proxmox_mcp_server import ProxmoxMCPServer

# Try to import python-dotenv
try:
    from dotenv import load_dotenv
    HAS_DOTENV = True
except ImportError:
    HAS_DOTENV = False

logger = logging.getLogger(__name__)

class ProxmoxEnterpriseServer(ProxmoxMCPServer):
    """Enhanced MCP server with multi-node capabilities and advanced security"""
    
    def __init__(self, env_file: Optional[str] = None):
        # Load test environment config
        if not env_file:
            env_file = Path(__file__).parent.parent / "config" / ".env.proxmox-test"
        
        # Setup test environment
        self.test_env_path = Path(__file__).parent.parent
        self.setup_test_environment()
        
        super().__init__(str(env_file))
        
        # Enhanced features
        self.test_container_id = None
        self.audit_log_path = self.test_env_path / "logs" / "audit.log"
        
    def setup_test_environment(self):
        """Setup test environment directories and logging"""
        logs_dir = self.test_env_path / "logs"
        logs_dir.mkdir(exist_ok=True)
        
        # Setup enhanced logging
        log_file = logs_dir / "proxmox_enterprise.log"
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stderr)
            ]
        )
        
    def audit_log(self, action: str, details: Dict):
        """Log actions for audit trail"""
        audit_entry = {
            "timestamp": datetime.now().isoformat(),
            "action": action,
            "details": details,
            "source": "claude-mcp-server"
        }
        
        with open(self.audit_log_path, 'a') as f:
            f.write(json.dumps(audit_entry) + "\n")
    
    async def create_test_container(self) -> Dict:
        """Create a dedicated test container for this session"""
        logger.info("🚀 Creating test container...")
        
        # Get configuration
        ct_id = int(os.getenv("TEST_CONTAINER_ID", "999"))
        template = os.getenv("TEST_CONTAINER_TEMPLATE", "ubuntu-22.04-standard")
        memory = int(os.getenv("TEST_CONTAINER_MEMORY", "512"))
        storage_size = int(os.getenv("TEST_CONTAINER_STORAGE", "2048"))
        network = os.getenv("TEST_CONTAINER_NETWORK", "vmbr0")
        ip_config = os.getenv("TEST_CONTAINER_IP", "dhcp")
        
        self.audit_log("create_container_attempt", {
            "container_id": ct_id,
            "template": template,
            "memory": memory,
            "storage": storage_size
        })
        
        try:
            await self._connect_proxmox()
            
            # Check if container ID is available
            try:
                existing = self.proxmox.nodes('pve').lxc(ct_id).status.current.get()
                return {
                    "error": f"Container {ct_id} already exists",
                    "existing_container": existing
                }
            except:
                # Container doesn't exist, we can create it
                pass
            
            # Create container
            create_params = {
                "vmid": ct_id,
                "template": f"local:vztmpl/{template}_amd64.tar.xz",
                "memory": memory,
                "swap": 512,
                "cores": 1,
                "storage": "local-lvm",
                "rootfs": f"local-lvm:{storage_size//1024}",
                "net0": f"name=eth0,bridge={network},ip={ip_config}",
                "hostname": f"claude-test-{ct_id}",
                "password": "test123!",  # Temporary password, will use SSH keys
                "onboot": 0,
                "unprivileged": 1,
                "description": "Claude MCP Test Container - Auto-created for testing"
            }
            
            logger.info(f"Creating container {ct_id} with template {template}...")
            result = self.proxmox.nodes('pve').lxc.post(**create_params)
            
            self.test_container_id = ct_id
            
            self.audit_log("create_container_success", {
                "container_id": ct_id,
                "result": result
            })
            
            return {
                "success": True,
                "container_id": ct_id,
                "result": result,
                "message": f"Test container {ct_id} created successfully"
            }
            
        except Exception as e:
            self.audit_log("create_container_error", {
                "container_id": ct_id,
                "error": str(e)
            })
            
            return {
                "error": f"Failed to create container: {str(e)}",
                "container_id": ct_id
            }
    
    async def setup_test_container_access(self) -> Dict:
        """Setup SSH access to the test container"""
        if not self.test_container_id:
            return {"error": "No test container created yet"}
        
        try:
            logger.info("🔧 Setting up SSH access to test container...")
            
            # Start the container first
            logger.info(f"Starting container {self.test_container_id}...")
            self.proxmox.nodes('pve').lxc(self.test_container_id).status.start.post()
            
            # Wait a moment for container to start
            await asyncio.sleep(5)
            
            # Get container IP
            config = self.proxmox.nodes('pve').lxc(self.test_container_id).config.get()
            status = self.proxmox.nodes('pve').lxc(self.test_container_id).status.current.get()
            
            self.audit_log("setup_container_access", {
                "container_id": self.test_container_id,
                "status": status.get("status"),
                "config": config
            })
            
            return {
                "success": True,
                "container_id": self.test_container_id,
                "status": status,
                "config": config,
                "message": "Container started and ready for SSH setup"
            }
            
        except Exception as e:
            self.audit_log("setup_container_error", {
                "container_id": self.test_container_id,
                "error": str(e)
            })
            
            return {
                "error": f"Failed to setup container access: {str(e)}"
            }
    
    async def cleanup_test_container(self) -> Dict:
        """Clean up test container when done"""
        if not self.test_container_id:
            return {"message": "No test container to clean up"}
        
        try:
            logger.info(f"🧹 Cleaning up test container {self.test_container_id}...")
            
            # Stop container
            self.proxmox.nodes('pve').lxc(self.test_container_id).status.stop.post()
            
            # Wait for stop
            await asyncio.sleep(3)
            
            # Destroy container
            self.proxmox.nodes('pve').lxc(self.test_container_id).delete()
            
            self.audit_log("cleanup_container", {
                "container_id": self.test_container_id,
                "action": "destroyed"
            })
            
            container_id = self.test_container_id
            self.test_container_id = None
            
            return {
                "success": True,
                "message": f"Test container {container_id} cleaned up successfully"
            }
            
        except Exception as e:
            self.audit_log("cleanup_container_error", {
                "container_id": self.test_container_id,
                "error": str(e)
            })
            
            return {
                "error": f"Failed to cleanup container: {str(e)}"
            }

def main():
    """Main entry point for testing"""
    server = ProxmoxEnterpriseServer()
    logger.info("🎯 Proxmox Enterprise MCP Server started in test mode")
    return server

if __name__ == "__main__":
    server = main()
    asyncio.run(server.run())