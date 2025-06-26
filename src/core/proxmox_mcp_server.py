#!/usr/bin/env python3
"""
Proxmox MCP Server - Model Context Protocol for Proxmox VE Management
Provides secure terminal access and Proxmox API integration for AI assistants
"""

import asyncio
import json
import logging
import os
import subprocess
import sys
from typing import Dict, List, Optional, Any
from datetime import datetime
from pathlib import Path
import argparse
import aiohttp
import urllib3
from proxmoxer import ProxmoxAPI
import paramiko
from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
import mcp.server.stdio
import mcp.types as types

# Import environment manager
try:
    from .environment_manager import EnvironmentManager
except ImportError:
    from environment_manager import EnvironmentManager

# Try to import python-dotenv
try:
    from dotenv import load_dotenv
    HAS_DOTENV = True
except ImportError:
    HAS_DOTENV = False
    print("Warning: python-dotenv not installed. Install with: pip install python-dotenv")
    print("Continuing without .env file support...")

# Disable SSL warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ProxmoxMCPServer:
    def __init__(self, env_file: Optional[str] = None):
        self.server = Server("proxmox-mcp")
        self.proxmox = None
        self.ssh_client = None
        self.env_file = env_file
        self.env_manager = EnvironmentManager()
        self.config = self._load_config()
        
        # Log environment information
        self._log_environment_info()
        
        # Register handlers
        self._register_handlers()
    
    def _load_config(self) -> Dict:
        """Load configuration from environment variables or config file"""
        # Load .env file if specified and python-dotenv is available
        if HAS_DOTENV:
            if self.env_file:
                # Load specific .env file with proper path resolution
                env_path = Path(self.env_manager.resolve_path(self.env_file))
                if env_path.exists():
                    load_dotenv(env_path)
                    logger.info(f"Loaded environment from: {env_path}")
                else:
                    logger.warning(f"Environment file not found: {env_path}")
            else:
                # Try to load default .env file from project root
                project_root = self.env_manager.get_project_root()
                default_env = project_root / '.env'
                if default_env.exists():
                    load_dotenv(default_env)
                    logger.info(f"Loaded environment from: {default_env}")
                else:
                    # Also try current directory as fallback
                    fallback_env = Path('.env')
                    if fallback_env.exists():
                        load_dotenv(fallback_env)
                        logger.info("Loaded environment from current directory .env file")
        
        config = {
            # SSH Configuration
            "ssh_target": os.getenv("SSH_TARGET", "container"),  # container or proxmox
            "ssh_host": os.getenv("SSH_HOST", "192.168.1.150"),
            "ssh_user": os.getenv("SSH_USER", "academic"),
            "ssh_password": os.getenv("SSH_PASSWORD"),  # Optional fallback
            "ssh_key_path": os.getenv("SSH_KEY_PATH"),  # Path to private key file
            "ssh_private_key": os.getenv("SSH_PRIVATE_KEY"),  # Private key content
            "ssh_key_passphrase": os.getenv("SSH_KEY_PASSPHRASE"),  # Key passphrase
            "ssh_port": int(os.getenv("SSH_PORT", "22")),
            
            # Proxmox API Configuration
            "proxmox_host": os.getenv("PROXMOX_HOST", "192.168.1.137"),
            "proxmox_user": os.getenv("PROXMOX_USER", "admin@pam"),
            "proxmox_password": os.getenv("PROXMOX_PASSWORD"),  # Optional fallback
            "proxmox_token_name": os.getenv("PROXMOX_TOKEN_NAME"),  # API token name
            "proxmox_token_value": os.getenv("PROXMOX_TOKEN_VALUE"),  # API token value
            "proxmox_verify_ssl": os.getenv("PROXMOX_VERIFY_SSL", "False").lower() == "true",
            
            # Feature Flags
            "enable_dangerous_commands": os.getenv("ENABLE_DANGEROUS_COMMANDS", "False").lower() == "true",
            "enable_proxmox_api": os.getenv("ENABLE_PROXMOX_API", "False").lower() == "true",
            "enable_local_execution": os.getenv("ENABLE_LOCAL_EXECUTION", "False").lower() == "true",
            "enable_ssh": os.getenv("ENABLE_SSH", "True").lower() == "true"
        }
        
        # Set defaults based on SSH target
        if config["ssh_target"] == "proxmox":
            if not config["ssh_host"]:
                config["ssh_host"] = config["proxmox_host"]
            if not config["ssh_user"]:
                config["ssh_user"] = "root"
        elif config["ssh_target"] == "container":
            if not config["ssh_host"]:
                config["ssh_host"] = "192.168.1.150"
            if not config["ssh_user"]:
                config["ssh_user"] = "academic"
        
        # Determine authentication methods
        auth_methods = []
        if config["ssh_key_path"] or config["ssh_private_key"]:
            auth_methods.append("ssh_key")
        if config["ssh_password"]:
            auth_methods.append("ssh_password")
        if config["proxmox_token_name"] and config["proxmox_token_value"]:
            auth_methods.append("api_token")
        if config["proxmox_password"]:
            auth_methods.append("api_password")
        
        # Resolve SSH key path using environment manager
        if config["ssh_key_path"]:
            config["ssh_key_path"] = self.env_manager.resolve_ssh_key_path(config["ssh_key_path"])
        
        # Log loaded configuration (without sensitive data)
        logger.info(f"Loaded config: target={config['ssh_target']}, ssh_host={config['ssh_host']}, ssh_user={config['ssh_user']}, ssh_port={config['ssh_port']}")
        logger.info(f"Authentication methods: {', '.join(auth_methods) if auth_methods else 'none configured'}")
        logger.info(f"Proxmox API enabled: {config['enable_proxmox_api']}")
        if config["ssh_key_path"]:
            logger.info(f"SSH key path resolved to: {config['ssh_key_path']}")
        
        # Try to load from config file if env vars not set
        config_file = os.path.expanduser("~/.config/proxmox-mcp/config.json")
        if os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    file_config = json.load(f)
                    # Only update missing values
                    for key, value in file_config.items():
                        if config.get(key) is None:
                            config[key] = value
                logger.info(f"Loaded additional config from {config_file}")
            except Exception as e:
                logger.warning(f"Failed to load config file {config_file}: {e}")
        
        return config
    
    def _log_environment_info(self):
        """Log detailed environment information for debugging"""
        env_info = self.env_manager.get_environment_info()
        logger.info(f"Environment detected: {env_info['environment_type']}")
        logger.info(f"Platform: {env_info['platform_system']} {env_info['platform_release']}")
        logger.info(f"Project root: {env_info['project_root']}")
        logger.info(f"Python executable: {env_info['python_executable']}")
        
        if env_info['windows_drive_mappings']:
            logger.info(f"Windows drive mappings: {env_info['windows_drive_mappings']}")
        
        if env_info['environment_variables']['WSL_DISTRO_NAME']:
            logger.info(f"WSL distribution: {env_info['environment_variables']['WSL_DISTRO_NAME']}")
    
    def _register_handlers(self):
        """Register all MCP handlers"""
        
        @self.server.list_resources()
        async def handle_list_resources() -> list[types.Resource]:
            resources = [
                types.Resource(
                    uri="proxmox://terminal",
                    name="Container SSH Terminal",
                    description="Execute commands on container via SSH",
                    mimeType="text/plain",
                ),
            ]
            
            # Only include API resource if Proxmox API is enabled
            if self.config["enable_proxmox_api"]:
                resources.append(
                    types.Resource(
                        uri="proxmox://api",
                        name="Proxmox API",
                        description="Access Proxmox API endpoints",
                        mimeType="application/json",
                    )
                )
            
            return resources
        
        @self.server.list_tools()
        async def handle_list_tools() -> list[types.Tool]:
            # Always include SSH command execution
            tools = [
                types.Tool(
                    name="execute_command",
                    description="Execute a shell command on the container via SSH",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The shell command to execute"
                            },
                            "timeout": {
                                "type": "integer",
                                "description": "Command timeout in seconds",
                                "default": 30
                            }
                        },
                        "required": ["command"]
                    }
                )
            ]
            
            # Only include Proxmox API tools if explicitly enabled
            if self.config["enable_proxmox_api"]:
                tools.extend([
                    types.Tool(
                        name="proxmox_api",
                        description="Make a Proxmox API call",
                        inputSchema={
                            "type": "object",
                            "properties": {
                                "method": {
                                    "type": "string",
                                    "enum": ["GET", "POST", "PUT", "DELETE"],
                                    "description": "HTTP method"
                                },
                                "path": {
                                    "type": "string",
                                    "description": "API path (e.g., /nodes, /vms)"
                                },
                                "data": {
                                    "type": "object",
                                    "description": "Request data for POST/PUT"
                                }
                            },
                            "required": ["method", "path"]
                        }
                    ),
                    types.Tool(
                        name="list_vms",
                        description="List all VMs across all nodes",
                        inputSchema={
                            "type": "object",
                            "properties": {}
                        }
                    ),
                    types.Tool(
                        name="vm_status",
                        description="Get detailed status of a specific VM",
                        inputSchema={
                            "type": "object",
                            "properties": {
                                "vmid": {
                                    "type": "integer",
                                    "description": "VM ID"
                                },
                                "node": {
                                    "type": "string",
                                    "description": "Node name where VM is located"
                                }
                            },
                            "required": ["vmid", "node"]
                        }
                    ),
                    types.Tool(
                        name="vm_action",
                        description="Perform an action on a VM (start, stop, restart, etc.)",
                        inputSchema={
                            "type": "object",
                            "properties": {
                                "vmid": {
                                    "type": "integer",
                                    "description": "VM ID"
                                },
                                "node": {
                                    "type": "string",
                                    "description": "Node name"
                                },
                                "action": {
                                    "type": "string",
                                    "enum": ["start", "stop", "restart", "shutdown", "suspend", "resume"],
                                    "description": "Action to perform"
                                }
                            },
                            "required": ["vmid", "node", "action"]
                        }
                    ),
                    types.Tool(
                        name="node_status",
                        description="Get status of Proxmox nodes",
                        inputSchema={
                            "type": "object",
                            "properties": {
                                "node": {
                                    "type": "string",
                                    "description": "Specific node name (optional)"
                                }
                            }
                        }
                    ),
                ])
            
            return tools
        
        @self.server.call_tool()
        async def handle_call_tool(
            name: str, arguments: Optional[Dict[str, Any]]
        ) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
            try:
                if name == "execute_command":
                    result = await self._execute_command(
                        arguments.get("command"),
                        arguments.get("timeout", 30)
                    )
                elif name in ["proxmox_api", "list_vms", "vm_status", "vm_action", "node_status"]:
                    if not self.config["enable_proxmox_api"]:
                        result = f"Proxmox API tools are disabled. Only SSH commands are available."
                    elif name == "proxmox_api":
                        result = await self._proxmox_api_call(
                            arguments.get("method"),
                            arguments.get("path"),
                            arguments.get("data")
                        )
                    elif name == "list_vms":
                        result = await self._list_vms()
                    elif name == "vm_status":
                        result = await self._vm_status(
                            arguments.get("vmid"),
                            arguments.get("node")
                        )
                    elif name == "vm_action":
                        result = await self._vm_action(
                            arguments.get("vmid"),
                            arguments.get("node"),
                            arguments.get("action")
                        )
                    elif name == "node_status":
                        result = await self._node_status(arguments.get("node"))
                else:
                    result = f"Unknown tool: {name}"
                
                return [types.TextContent(type="text", text=str(result))]
            
            except Exception as e:
                logger.error(f"Error in tool {name}: {str(e)}")
                return [types.TextContent(type="text", text=f"Error: {str(e)}")]
    
    async def _connect_proxmox(self):
        """Establish connection to Proxmox API"""
        if not self.proxmox:
            # Try API token authentication first
            if self.config["proxmox_token_name"] and self.config["proxmox_token_value"]:
                try:
                    logger.info("Attempting Proxmox API connection with token authentication")
                    self.proxmox = ProxmoxAPI(
                        self.config["proxmox_host"],
                        user=self.config["proxmox_user"],
                        token_name=self.config["proxmox_token_name"],
                        token_value=self.config["proxmox_token_value"],
                        verify_ssl=self.config["proxmox_verify_ssl"]
                    )
                    # Test the connection
                    await self._test_proxmox_connection()
                    logger.info("✅ Proxmox API token authentication successful")
                    return
                except Exception as e:
                    logger.warning(f"Proxmox API token authentication failed: {e}")
                    self.proxmox = None
            
            # Fall back to password authentication
            if self.config["proxmox_password"]:
                try:
                    logger.info("Attempting Proxmox API connection with password authentication")
                    self.proxmox = ProxmoxAPI(
                        self.config["proxmox_host"],
                        user=self.config["proxmox_user"],
                        password=self.config["proxmox_password"],
                        verify_ssl=self.config["proxmox_verify_ssl"]
                    )
                    # Test the connection
                    await self._test_proxmox_connection()
                    logger.info("✅ Proxmox API password authentication successful")
                    return
                except Exception as e:
                    logger.error(f"Proxmox API password authentication failed: {e}")
                    self.proxmox = None
                    raise
            
            raise Exception("No valid Proxmox API authentication method configured")
    
    async def _test_proxmox_connection(self):
        """Test Proxmox API connection"""
        if self.proxmox:
            # Simple test call
            self.proxmox.version.get()
    
    async def _connect_ssh(self):
        """Establish SSH connection for terminal access"""
        # Check if we need a new connection
        need_connection = False
        
        if not self.ssh_client:
            need_connection = True
        else:
            # Test if existing connection is still active
            try:
                transport = self.ssh_client.get_transport()
                if not transport or not transport.is_active():
                    need_connection = True
            except:
                need_connection = True
        
        if need_connection:
            # Close existing connection if any
            if self.ssh_client:
                try:
                    self.ssh_client.close()
                except:
                    pass
            
            # Create new connection with multiple authentication methods
            self.ssh_client = paramiko.SSHClient()
            self.ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # Prepare connection parameters
            connect_params = {
                "hostname": self.config["ssh_host"],
                "port": self.config["ssh_port"],
                "username": self.config["ssh_user"],
                "timeout": 10
            }
            
            # Try SSH key authentication first
            key_auth_success = False
            if self.config["ssh_key_path"] or self.config["ssh_private_key"]:
                try:
                    logger.info(f"Attempting SSH key authentication to {self.config['ssh_user']}@{self.config['ssh_host']}")
                    
                    if self.config["ssh_key_path"]:
                        # Load key from file with proper path resolution
                        key_path = self.config["ssh_key_path"]  # Already resolved in _load_config
                        if os.path.exists(key_path):
                            connect_params["key_filename"] = key_path
                            if self.config["ssh_key_passphrase"]:
                                connect_params["passphrase"] = self.config["ssh_key_passphrase"]
                            logger.debug(f"Using SSH key file: {key_path}")
                        else:
                            logger.warning(f"SSH key file not found: {key_path}")
                            # Try to resolve path again in case of cross-platform issues
                            fallback_path = self.env_manager.resolve_ssh_key_path(self.config["ssh_key_path"])
                            if fallback_path != key_path and os.path.exists(fallback_path):
                                connect_params["key_filename"] = fallback_path
                                if self.config["ssh_key_passphrase"]:
                                    connect_params["passphrase"] = self.config["ssh_key_passphrase"]
                                logger.info(f"Using fallback SSH key path: {fallback_path}")
                            else:
                                logger.error(f"SSH key file not accessible: {key_path}")
                    
                    elif self.config["ssh_private_key"]:
                        # Load key from content
                        from io import StringIO
                        key_content = StringIO(self.config["ssh_private_key"])
                        try:
                            # Try different key types
                            for key_class in [paramiko.RSAKey, paramiko.Ed25519Key, paramiko.ECDSAKey, paramiko.DSSKey]:
                                try:
                                    pkey = key_class.from_private_key(
                                        key_content, 
                                        password=self.config["ssh_key_passphrase"]
                                    )
                                    connect_params["pkey"] = pkey
                                    break
                                except Exception:
                                    key_content.seek(0)  # Reset for next attempt
                                    continue
                        except Exception as e:
                            logger.warning(f"Failed to parse SSH private key: {e}")
                    
                    # Attempt connection with key
                    if "key_filename" in connect_params or "pkey" in connect_params:
                        self.ssh_client.connect(**connect_params)
                        key_auth_success = True
                        logger.info("✅ SSH key authentication successful")
                
                except Exception as e:
                    logger.warning(f"SSH key authentication failed: {e}")
                    # Reset client for password attempt
                    try:
                        self.ssh_client.close()
                    except:
                        pass
                    self.ssh_client = paramiko.SSHClient()
                    self.ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # Fall back to password authentication if key auth failed
            if not key_auth_success and self.config["ssh_password"]:
                try:
                    logger.info(f"Attempting SSH password authentication to {self.config['ssh_user']}@{self.config['ssh_host']}")
                    connect_params = {
                        "hostname": self.config["ssh_host"],
                        "port": self.config["ssh_port"],
                        "username": self.config["ssh_user"],
                        "password": self.config["ssh_password"],
                        "timeout": 10
                    }
                    self.ssh_client.connect(**connect_params)
                    logger.info("✅ SSH password authentication successful")
                
                except Exception as e:
                    logger.error(f"SSH password authentication failed: {e}")
                    self.ssh_client = None
                    raise
            
            elif not key_auth_success:
                self.ssh_client = None
                raise Exception("No valid SSH authentication method configured")
    
    async def _execute_command(self, command: str, timeout: int = 30) -> str:
        """Execute a shell command either locally or via SSH"""
        # Safety check for dangerous commands
        dangerous_commands = ['rm -rf /', 'dd if=/dev/zero', 'mkfs', ':(){ :|:& };:']
        if not self.config["enable_dangerous_commands"]:
            for dangerous in dangerous_commands:
                if dangerous in command:
                    return json.dumps({
                        "command": command,
                        "error": f"Command blocked for safety: {command}",
                        "stdout": "",
                        "stderr": "",
                        "exit_status": -1,
                        "timestamp": datetime.now().isoformat()
                    }, indent=2)
        
        try:
            # Use local execution if enabled and SSH is disabled
            if self.config["enable_local_execution"] and not self.config["enable_ssh"]:
                logger.info(f"Executing command locally: {command}")
                
                # Execute command locally using subprocess
                process = await asyncio.create_subprocess_shell(
                    command,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                
                try:
                    stdout_data, stderr_data = await asyncio.wait_for(
                        process.communicate(), timeout=timeout
                    )
                    
                    result = {
                        "command": command,
                        "stdout": stdout_data.decode('utf-8'),
                        "stderr": stderr_data.decode('utf-8'),
                        "exit_status": process.returncode,
                        "timestamp": datetime.now().isoformat()
                    }
                    
                    return json.dumps(result, indent=2)
                    
                except asyncio.TimeoutError:
                    process.kill()
                    await process.wait()
                    result = {
                        "command": command,
                        "error": f"Command timed out after {timeout} seconds",
                        "stdout": "",
                        "stderr": "",
                        "exit_status": -1,
                        "timestamp": datetime.now().isoformat()
                    }
                    return json.dumps(result, indent=2)
            
            else:
                # Use SSH execution (existing behavior)
                logger.info(f"Executing command via SSH: {command}")
                await self._connect_ssh()
                
                # Verify SSH client is ready
                if not self.ssh_client or not self.ssh_client.get_transport() or not self.ssh_client.get_transport().is_active():
                    raise Exception("SSH connection not active")
                
                stdin, stdout, stderr = self.ssh_client.exec_command(command, timeout=timeout)
                
                output = stdout.read().decode('utf-8')
                error = stderr.read().decode('utf-8')
                
                result = {
                    "command": command,
                    "stdout": output,
                    "stderr": error,
                    "exit_status": stdout.channel.recv_exit_status(),
                    "timestamp": datetime.now().isoformat()
                }
                
                return json.dumps(result, indent=2)
            
        except Exception as e:
            execution_method = "local" if (self.config["enable_local_execution"] and not self.config["enable_ssh"]) else "SSH"
            logger.error(f"{execution_method} command execution failed: {str(e)}")
            error_result = {
                "command": command,
                "error": f"{execution_method} execution failed: {str(e)}",
                "stdout": "",
                "stderr": "",
                "exit_status": -1,
                "timestamp": datetime.now().isoformat()
            }
            return json.dumps(error_result, indent=2)
    
    async def _proxmox_api_call(self, method: str, path: str, data: Optional[Dict] = None) -> str:
        """Make a direct Proxmox API call"""
        await self._connect_proxmox()
        
        # Parse the path to extract the API components
        path_parts = path.strip('/').split('/')
        
        # Navigate through the API structure
        api_endpoint = self.proxmox
        for part in path_parts:
            api_endpoint = getattr(api_endpoint, part)
        
        # Make the API call
        if method == "GET":
            result = api_endpoint.get()
        elif method == "POST":
            result = api_endpoint.post(**data) if data else api_endpoint.post()
        elif method == "PUT":
            result = api_endpoint.put(**data) if data else api_endpoint.put()
        elif method == "DELETE":
            result = api_endpoint.delete()
        else:
            raise ValueError(f"Unsupported method: {method}")
        
        return json.dumps(result, indent=2)
    
    async def _list_vms(self) -> str:
        """List all VMs across all nodes"""
        await self._connect_proxmox()
        
        vms = []
        for node in self.proxmox.nodes.get():
            node_name = node['node']
            for vm in self.proxmox.nodes(node_name).qemu.get():
                vm['node'] = node_name
                vms.append(vm)
        
        return json.dumps(vms, indent=2)
    
    async def _vm_status(self, vmid: int, node: str) -> str:
        """Get detailed status of a specific VM"""
        await self._connect_proxmox()
        
        status = self.proxmox.nodes(node).qemu(vmid).status.current.get()
        config = self.proxmox.nodes(node).qemu(vmid).config.get()
        
        result = {
            "status": status,
            "config": config
        }
        
        return json.dumps(result, indent=2)
    
    async def _vm_action(self, vmid: int, node: str, action: str) -> str:
        """Perform an action on a VM"""
        await self._connect_proxmox()
        
        vm_api = self.proxmox.nodes(node).qemu(vmid)
        
        if action == "start":
            result = vm_api.status.start.post()
        elif action == "stop":
            result = vm_api.status.stop.post()
        elif action == "restart":
            result = vm_api.status.reboot.post()
        elif action == "shutdown":
            result = vm_api.status.shutdown.post()
        elif action == "suspend":
            result = vm_api.status.suspend.post()
        elif action == "resume":
            result = vm_api.status.resume.post()
        else:
            raise ValueError(f"Unknown action: {action}")
        
        return json.dumps({
            "action": action,
            "vmid": vmid,
            "node": node,
            "result": result,
            "timestamp": datetime.now().isoformat()
        }, indent=2)
    
    async def _node_status(self, node: Optional[str] = None) -> str:
        """Get status of Proxmox nodes"""
        await self._connect_proxmox()
        
        if node:
            status = self.proxmox.nodes(node).status.get()
        else:
            # Get all nodes status
            nodes = []
            for n in self.proxmox.nodes.get():
                node_name = n['node']
                status = self.proxmox.nodes(node_name).status.get()
                status['node'] = node_name
                nodes.append(status)
            return json.dumps(nodes, indent=2)
        
        return json.dumps(status, indent=2)
    
    def cleanup(self):
        """Cleanup connections"""
        if self.ssh_client:
            try:
                self.ssh_client.close()
            except:
                pass
            self.ssh_client = None
    
    async def run(self):
        """Run the MCP server with robust STDIO error handling"""
        try:
            # Add small delay to ensure Claude Code is ready
            await asyncio.sleep(0.1)
            
            # Flush STDIO streams before starting
            sys.stdout.flush()
            sys.stderr.flush()
            
            logger.info("Starting MCP STDIO server...")
            async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
                logger.info("STDIO streams established successfully")
                await self.server.run(
                    read_stream,
                    write_stream,
                    InitializationOptions(
                        server_name="proxmox-mcp",
                        server_version="1.0.0",
                        capabilities=self.server.get_capabilities(
                            notification_options=NotificationOptions(),
                            experimental_capabilities={},
                        ),
                    ),
                )
        except BrokenPipeError as e:
            logger.error(f"STDIO pipe closed by client: {e}")
            logger.info("This typically happens when Claude Code closes the connection")
            # Exit gracefully instead of crashing
            return
        except OSError as e:
            if e.errno == 32:  # Broken pipe
                logger.error(f"Broken pipe error (errno 32): {e}")
                logger.info("Client disconnected, exiting gracefully")
                return
            else:
                logger.error(f"OS error during STDIO communication: {e}")
                raise
        except Exception as e:
            logger.error(f"Unexpected error in MCP server: {e}")
            raise

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='Proxmox MCP Server')
    parser.add_argument('--env-file', type=str, help='Path to .env file to load')
    args = parser.parse_args()
    
    server = ProxmoxMCPServer(env_file=args.env_file)
    asyncio.run(server.run())

if __name__ == "__main__":
    main()