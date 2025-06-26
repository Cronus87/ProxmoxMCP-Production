#!/usr/bin/env python3
"""
Test script to reproduce the call_tool error
"""
import os
import sys
from pathlib import Path

# Add core to Python path
script_dir = Path(__file__).parent
core_path = script_dir / "core"
sys.path.insert(0, str(core_path))

try:
    from proxmox_mcp_server import ProxmoxMCPServer
    
    # Create server instance
    server = ProxmoxMCPServer()
    print("✅ ProxmoxMCPServer created successfully")
    
    # Check what methods are available
    print("\n📋 Available methods on ProxmoxMCPServer:")
    methods = [method for method in dir(server) if not method.startswith('_')]
    for method in methods:
        print(f"  - {method}")
    
    # Check if call_tool method exists
    if hasattr(server, 'call_tool'):
        print("\n✅ call_tool method exists")
    else:
        print("\n❌ call_tool method does NOT exist")
        
    # Check what the server attribute contains (this is the actual MCP server)
    print("\n🔍 server.server attributes:")
    server_methods = [method for method in dir(server.server) if not method.startswith('_')]
    for method in server_methods:
        print(f"  - {method}")
        
    # Check if the MCP server has call_tool
    if hasattr(server.server, 'call_tool'):
        print("\n✅ server.server.call_tool method exists")
    else:
        print("\n❌ server.server.call_tool method does NOT exist")

except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()