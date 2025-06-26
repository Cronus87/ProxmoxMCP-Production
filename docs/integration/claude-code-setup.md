# Proxmox MCP - Integration Guide

**Complete guide for integrating Proxmox MCP with Claude Code and other systems**

## Overview

This guide covers all aspects of integrating the Proxmox MCP server with Claude Code clients, development environments, and enterprise systems. It provides detailed instructions for various integration scenarios and troubleshooting common integration issues.

## Table of Contents

1. [Claude Code Integration](#claude-code-integration)
2. [Development Environment Setup](#development-environment-setup)
3. [Enterprise Integration](#enterprise-integration)
4. [API Integration](#api-integration)
5. [Monitoring Integration](#monitoring-integration)
6. [Security Integration](#security-integration)
7. [Custom Integrations](#custom-integrations)
8. [Integration Testing](#integration-testing)

---

## Claude Code Integration

### Basic Claude Code Setup

**Global Configuration (Recommended):**
```json
{
  "mcpServers": {
    "proxmox-production": {
      "type": "http",
      "url": "http://192.168.1.137:8080/api/mcp",
      "name": "Proxmox Production Environment",
      "description": "Production Proxmox VE management tools",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "Claude-Code-MCP-Client/1.0"
      },
      "timeout": 30000,
      "retries": 3
    }
  }
}
```

**Project-Specific Configuration:**
```json
{
  "mcpServers": {
    "proxmox-lab": {
      "type": "http",
      "url": "http://192.168.1.137:8080/api/mcp",
      "name": "Proxmox Lab Environment",
      "description": "Development and testing Proxmox tools",
      "headers": {
        "Content-Type": "application/json",
        "X-Environment": "development",
        "X-Project": "my-project"
      }
    }
  }
}
```

### Advanced Claude Code Configuration

**Multi-Environment Setup:**
```json
{
  "mcpServers": {
    "proxmox-production": {
      "type": "http",
      "url": "https://proxmox-prod.company.com/api/mcp",
      "name": "Proxmox Production",
      "description": "Production Proxmox environment",
      "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer YOUR_API_KEY",
        "X-Environment": "production"
      },
      "timeout": 45000
    },
    "proxmox-staging": {
      "type": "http", 
      "url": "https://proxmox-stage.company.com/api/mcp",
      "name": "Proxmox Staging",
      "description": "Staging Proxmox environment",
      "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer YOUR_STAGING_KEY",
        "X-Environment": "staging"
      },
      "timeout": 30000
    },
    "proxmox-development": {
      "type": "http",
      "url": "http://192.168.1.137:8080/api/mcp", 
      "name": "Proxmox Development",
      "description": "Development Proxmox environment",
      "headers": {
        "Content-Type": "application/json",
        "X-Environment": "development"
      },
      "timeout": 15000
    }
  }
}
```

**Load Balancer Configuration:**
```json
{
  "mcpServers": {
    "proxmox-cluster": {
      "type": "http",
      "url": "https://proxmox-lb.company.com/api/mcp",
      "name": "Proxmox Cluster",
      "description": "Load-balanced Proxmox cluster access",
      "headers": {
        "Content-Type": "application/json",
        "X-Load-Balance": "round-robin",
        "X-Failover": "automatic"
      },
      "timeout": 60000,
      "retries": 5
    }
  }
}
```

### Configuration Validation

**Validate Claude Code Configuration:**
```bash
# Check JSON syntax
python3 -m json.tool ~/.claude.json

# Test MCP connectivity
curl -X POST http://192.168.1.137:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}'

# Validate tool availability
curl -X POST http://192.168.1.137:8080/api/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_vms","arguments":{}},"id":"test"}'
```

**Configuration Testing Script:**
```bash
#!/bin/bash
# claude-integration-test.sh

CONFIG_FILE="$HOME/.claude.json"
echo "Testing Claude Code MCP integration..."

# Check configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Claude configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Validate JSON syntax
if ! python3 -m json.tool "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "❌ Invalid JSON syntax in $CONFIG_FILE"
    exit 1
fi

echo "✅ Configuration file syntax valid"

# Extract MCP server URLs
urls=$(jq -r '.mcpServers[].url' "$CONFIG_FILE" 2>/dev/null)

if [ -z "$urls" ]; then
    echo "❌ No MCP servers configured"
    exit 1
fi

# Test each MCP server
for url in $urls; do
    echo "Testing MCP server: $url"
    
    # Test health endpoint
    health_url="${url%/api/mcp}/health"
    if curl -s -f "$health_url" >/dev/null 2>&1; then
        echo "  ✅ Health endpoint accessible"
    else
        echo "  ❌ Health endpoint failed"
        continue
    fi
    
    # Test MCP tools list
    if curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"test"}' | \
        jq -e '.result.tools' >/dev/null 2>&1; then
        echo "  ✅ MCP tools accessible"
    else
        echo "  ❌ MCP tools not accessible"
    fi
done

echo "✅ Integration test completed"
```

---

## Development Environment Setup

### Local Development Integration

**Development Configuration:**
```json
{
  "mcpServers": {
    "proxmox-dev": {
      "type": "http",
      "url": "http://localhost:8080/api/mcp",
      "name": "Local Proxmox Development",
      "description": "Local development Proxmox MCP server",
      "headers": {
        "Content-Type": "application/json",
        "X-Development": "true",
        "X-Debug": "enabled"
      },
      "timeout": 10000
    }
  },
  "devMode": true,
  "logging": {
    "level": "debug",
    "mcpRequests": true
  }
}
```

### IDE Integration

**VS Code Integration:**
```json
// .vscode/settings.json
{
  "claude.mcpServers": {
    "proxmox-local": {
      "type": "http",
      "url": "http://localhost:8080/api/mcp",
      "autoConnect": true
    }
  },
  "claude.autoComplete.includeProxmox": true,
  "claude.proxmox.showVMStatus": true
}
```

**JetBrains Integration:**
```xml
<!-- .idea/claude-mcp.xml -->
<component name="ClaudeMCPConfiguration">
  <servers>
    <server name="proxmox-dev" 
            url="http://localhost:8080/api/mcp"
            type="http"
            autoConnect="true" />
  </servers>
  <features>
    <feature name="proxmox-autocomplete" enabled="true" />
    <feature name="vm-status-inline" enabled="true" />
  </features>
</component>
```

### Docker Development Environment

**Development Docker Compose:**
```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  mcp-server-dev:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "8080:8080"
    environment:
      - LOG_LEVEL=DEBUG
      - ENABLE_DEVELOPMENT_MODE=true
      - ENABLE_CORS=true
    volumes:
      - ./core:/app/core:ro
      - ./tests:/app/tests:ro
      - dev_logs:/app/logs
    restart: unless-stopped

  mcp-docs:
    image: nginx:alpine
    ports:
      - "8081:80"
    volumes:
      - ./docs:/usr/share/nginx/html:ro
    restart: unless-stopped

volumes:
  dev_logs:
```

**Development Startup Script:**
```bash
#!/bin/bash
# dev-start.sh

echo "Starting Proxmox MCP development environment..."

# Start development services
docker-compose -f docker-compose.dev.yml up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 10

# Test development setup
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    echo "✅ MCP server is running"
else
    echo "❌ MCP server failed to start"
    exit 1
fi

# Configure Claude Code for development
if [ ! -f ~/.claude.dev.json ]; then
    cat > ~/.claude.dev.json << 'EOF'
{
  "mcpServers": {
    "proxmox-dev": {
      "type": "http",
      "url": "http://localhost:8080/api/mcp",
      "name": "Development Proxmox MCP"
    }
  }
}
EOF
    echo "✅ Development configuration created"
fi

echo "Development environment ready!"
echo "MCP Server: http://localhost:8080"
echo "Documentation: http://localhost:8081"
echo "Use: claude --config ~/.claude.dev.json"
```

---

## Enterprise Integration

### Single Sign-On (SSO) Integration

**OIDC Integration:**
```yaml
# docker-compose.enterprise.yml
services:
  mcp-server:
    environment:
      - ENABLE_OIDC=true
      - OIDC_PROVIDER_URL=https://auth.company.com
      - OIDC_CLIENT_ID=proxmox-mcp
      - OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
      - OIDC_REDIRECT_URI=https://proxmox-mcp.company.com/auth/callback
    depends_on:
      - oauth-proxy

  oauth-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    ports:
      - "4180:4180"
    environment:
      - OAUTH2_PROXY_PROVIDER=oidc
      - OAUTH2_PROXY_OIDC_ISSUER_URL=https://auth.company.com
      - OAUTH2_PROXY_CLIENT_ID=proxmox-mcp
      - OAUTH2_PROXY_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
      - OAUTH2_PROXY_COOKIE_SECRET=${COOKIE_SECRET}
      - OAUTH2_PROXY_UPSTREAMS=http://mcp-server:8080
```

**LDAP Authentication:**
```python
# enterprise_auth.py
import ldap3
from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer

class LDAPAuthenticator:
    def __init__(self, server_url: str, base_dn: str):
        self.server_url = server_url
        self.base_dn = base_dn
    
    def authenticate(self, username: str, password: str) -> bool:
        try:
            server = ldap3.Server(self.server_url)
            user_dn = f"uid={username},{self.base_dn}"
            conn = ldap3.Connection(server, user_dn, password)
            return conn.bind()
        except Exception:
            return False

    def get_user_groups(self, username: str) -> list:
        # Implementation for group membership
        pass

# FastAPI integration
security = HTTPBearer()

async def authenticate_user(token: str = Depends(security)):
    # Verify JWT token or session
    pass
```

### Enterprise Monitoring Integration

**Splunk Integration:**
```bash
# splunk-forwarder.conf
[monitor:///var/log/sudo-claude-user.log]
index = proxmox_mcp
sourcetype = proxmox:audit
source = sudo_audit

[monitor:///var/log/proxmox-mcp-security.log]
index = security
sourcetype = proxmox:security
source = security_events

[monitor:///opt/proxmox-mcp/logs/]
index = proxmox_mcp
sourcetype = proxmox:application
source = mcp_application
```

**Datadog Integration:**
```yaml
# datadog-agent.yml
logs:
  - type: file
    path: /var/log/sudo-claude-user.log
    service: proxmox-mcp
    source: sudo-audit
    tags:
      - env:production
      - component:security

  - type: file
    path: /opt/proxmox-mcp/logs/*.log
    service: proxmox-mcp
    source: application
    tags:
      - env:production
      - component:mcp-server

apm:
  enabled: true
  env: production
  service: proxmox-mcp
  version: 1.0.0
```

**ELK Stack Integration:**
```yaml
# logstash.conf
input {
  file {
    path => "/var/log/sudo-claude-user.log"
    type => "sudo-audit"
    codec => "plain"
  }
  
  file {
    path => "/opt/proxmox-mcp/logs/app.log"
    type => "application"
    codec => "json"
  }
}

filter {
  if [type] == "sudo-audit" {
    grok {
      match => { "message" => "%{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:hostname} sudo: %{USERNAME:user} : TTY=%{TTY:tty} ; PWD=%{PATH:pwd} ; USER=%{USERNAME:target_user} ; COMMAND=%{GREEDYDATA:command}" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "proxmox-mcp-%{+YYYY.MM.dd}"
  }
}
```

### RBAC Integration

**Role-Based Access Control:**
```json
{
  "roles": {
    "proxmox-admin": {
      "description": "Full Proxmox administration access",
      "permissions": [
        "vm:create", "vm:delete", "vm:start", "vm:stop",
        "container:create", "container:delete", "container:start", "container:stop",
        "storage:create", "storage:delete", "node:manage"
      ]
    },
    "proxmox-operator": {
      "description": "Proxmox operational access",
      "permissions": [
        "vm:start", "vm:stop", "vm:restart", "vm:status",
        "container:start", "container:stop", "container:restart", "container:status",
        "node:status", "storage:status"
      ]
    },
    "proxmox-viewer": {
      "description": "Read-only Proxmox access",
      "permissions": [
        "vm:status", "container:status", "node:status", "storage:status"
      ]
    }
  },
  "users": {
    "admin@company.com": ["proxmox-admin"],
    "ops@company.com": ["proxmox-operator"],
    "dev@company.com": ["proxmox-viewer"]
  }
}
```

---

## API Integration

### REST API Integration

**Python Client Example:**
```python
import requests
import json
from typing import Dict, List, Optional

class ProxmoxMCPClient:
    def __init__(self, base_url: str, timeout: int = 30):
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })
    
    def _call_mcp(self, method: str, params: Dict = None) -> Dict:
        """Make MCP JSON-RPC call"""
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": "client"
        }
        
        response = self.session.post(
            f"{self.base_url}/api/mcp",
            json=payload,
            timeout=self.timeout
        )
        response.raise_for_status()
        
        result = response.json()
        if 'error' in result:
            raise Exception(f"MCP Error: {result['error']}")
        
        return result.get('result', {})
    
    def list_tools(self) -> List[Dict]:
        """Get available MCP tools"""
        result = self._call_mcp("tools/list")
        return result.get('tools', [])
    
    def list_vms(self) -> List[Dict]:
        """List all VMs"""
        return self._call_mcp("tools/call", {
            "name": "list_vms",
            "arguments": {}
        })
    
    def vm_status(self, vmid: int, node: str) -> Dict:
        """Get VM status"""
        return self._call_mcp("tools/call", {
            "name": "vm_status", 
            "arguments": {"vmid": vmid, "node": node}
        })
    
    def vm_action(self, vmid: int, node: str, action: str) -> Dict:
        """Perform VM action"""
        return self._call_mcp("tools/call", {
            "name": "vm_action",
            "arguments": {"vmid": vmid, "node": node, "action": action}
        })
    
    def execute_command(self, command: str, timeout: int = 30) -> Dict:
        """Execute command on Proxmox"""
        return self._call_mcp("tools/call", {
            "name": "execute_command",
            "arguments": {"command": command, "timeout": timeout}
        })

# Usage example
client = ProxmoxMCPClient("http://192.168.1.137:8080")

# List available tools
tools = client.list_tools()
print(f"Available tools: {[tool['name'] for tool in tools]}")

# List VMs
vms = client.list_vms()
print(f"Found {len(vms)} VMs")

# Start a VM
result = client.vm_action(vmid=101, node="proxmox", action="start")
print(f"VM start result: {result}")
```

**Node.js Client Example:**
```javascript
// proxmox-mcp-client.js
const axios = require('axios');

class ProxmoxMCPClient {
    constructor(baseUrl, timeout = 30000) {
        this.baseUrl = baseUrl.replace(/\/$/, '');
        this.timeout = timeout;
        this.client = axios.create({
            timeout: this.timeout,
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
        });
    }

    async callMCP(method, params = {}) {
        const payload = {
            jsonrpc: "2.0",
            method: method,
            params: params,
            id: "client"
        };

        try {
            const response = await this.client.post(
                `${this.baseUrl}/api/mcp`,
                payload
            );

            if (response.data.error) {
                throw new Error(`MCP Error: ${JSON.stringify(response.data.error)}`);
            }

            return response.data.result || {};
        } catch (error) {
            throw new Error(`MCP Request failed: ${error.message}`);
        }
    }

    async listTools() {
        const result = await this.callMCP("tools/list");
        return result.tools || [];
    }

    async listVMs() {
        return await this.callMCP("tools/call", {
            name: "list_vms",
            arguments: {}
        });
    }

    async vmStatus(vmid, node) {
        return await this.callMCP("tools/call", {
            name: "vm_status",
            arguments: { vmid, node }
        });
    }

    async vmAction(vmid, node, action) {
        return await this.callMCP("tools/call", {
            name: "vm_action",
            arguments: { vmid, node, action }
        });
    }

    async executeCommand(command, timeout = 30) {
        return await this.callMCP("tools/call", {
            name: "execute_command",
            arguments: { command, timeout }
        });
    }
}

// Usage example
async function main() {
    const client = new ProxmoxMCPClient("http://192.168.1.137:8080");

    try {
        // List tools
        const tools = await client.listTools();
        console.log(`Available tools: ${tools.map(t => t.name).join(', ')}`);

        // List VMs
        const vms = await client.listVMs();
        console.log(`Found ${vms.length} VMs`);

        // Execute command
        const result = await client.executeCommand("uptime");
        console.log(`Command result: ${JSON.stringify(result, null, 2)}`);

    } catch (error) {
        console.error(`Error: ${error.message}`);
    }
}

module.exports = ProxmoxMCPClient;
```

### Webhook Integration

**Webhook Receiver:**
```python
# webhook_receiver.py
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Dict, Any
import hmac
import hashlib

app = FastAPI()

class WebhookPayload(BaseModel):
    event: str
    data: Dict[str, Any]
    timestamp: str

class ProxmoxWebhookHandler:
    def __init__(self, mcp_client):
        self.mcp_client = mcp_client
    
    async def handle_vm_event(self, event: str, vm_data: Dict):
        """Handle VM-related webhook events"""
        vmid = vm_data.get('vmid')
        node = vm_data.get('node')
        
        if event == "vm.started":
            # Update monitoring systems
            await self.update_monitoring(vmid, node, "running")
        elif event == "vm.stopped":
            # Clean up resources
            await self.cleanup_vm_resources(vmid, node)
        elif event == "vm.created":
            # Initialize VM configuration
            await self.initialize_vm(vmid, node)
    
    async def update_monitoring(self, vmid: int, node: str, status: str):
        """Update external monitoring systems"""
        # Implementation for monitoring updates
        pass
    
    async def cleanup_vm_resources(self, vmid: int, node: str):
        """Clean up VM resources"""
        # Implementation for resource cleanup
        pass

webhook_handler = ProxmoxWebhookHandler(mcp_client)

@app.post("/webhook/proxmox")
async def receive_webhook(
    payload: WebhookPayload,
    background_tasks: BackgroundTasks,
    signature: str = None
):
    # Verify webhook signature
    if signature:
        expected_signature = hmac.new(
            WEBHOOK_SECRET.encode(),
            payload.json().encode(),
            hashlib.sha256
        ).hexdigest()
        
        if not hmac.compare_digest(signature, expected_signature):
            raise HTTPException(status_code=401, detail="Invalid signature")
    
    # Process webhook in background
    background_tasks.add_task(
        webhook_handler.handle_vm_event,
        payload.event,
        payload.data
    )
    
    return {"status": "accepted"}
```

---

## Monitoring Integration

### Prometheus Integration

**Custom Metrics Exporter:**
```python
# prometheus_exporter.py
from prometheus_client import Counter, Histogram, Gauge, start_http_server
import time
import asyncio

class ProxmoxMCPMetrics:
    def __init__(self, mcp_client):
        self.mcp_client = mcp_client
        
        # Define metrics
        self.request_count = Counter(
            'proxmox_mcp_requests_total',
            'Total MCP requests',
            ['method', 'status']
        )
        
        self.request_duration = Histogram(
            'proxmox_mcp_request_duration_seconds',
            'MCP request duration',
            ['method']
        )
        
        self.vm_count = Gauge(
            'proxmox_vms_total',
            'Total number of VMs',
            ['node', 'status']
        )
        
        self.node_resources = Gauge(
            'proxmox_node_resources',
            'Node resource usage',
            ['node', 'resource']
        )
    
    async def collect_vm_metrics(self):
        """Collect VM metrics"""
        try:
            vms = await self.mcp_client.list_vms()
            vm_counts = {}
            
            for vm in vms:
                node = vm.get('node', 'unknown')
                status = vm.get('status', 'unknown')
                key = (node, status)
                vm_counts[key] = vm_counts.get(key, 0) + 1
            
            # Update metrics
            for (node, status), count in vm_counts.items():
                self.vm_count.labels(node=node, status=status).set(count)
                
        except Exception as e:
            print(f"Error collecting VM metrics: {e}")
    
    async def collect_node_metrics(self):
        """Collect node metrics"""
        try:
            nodes = await self.mcp_client.node_status()
            
            for node_data in nodes:
                node = node_data.get('node', 'unknown')
                
                # CPU usage
                cpu_usage = node_data.get('cpu', 0)
                self.node_resources.labels(node=node, resource='cpu').set(cpu_usage)
                
                # Memory usage
                memory_usage = node_data.get('mem', 0)
                memory_max = node_data.get('maxmem', 1)
                memory_percent = (memory_usage / memory_max) * 100 if memory_max > 0 else 0
                self.node_resources.labels(node=node, resource='memory').set(memory_percent)
                
        except Exception as e:
            print(f"Error collecting node metrics: {e}")
    
    async def start_collection(self, interval: int = 60):
        """Start metrics collection"""
        while True:
            await self.collect_vm_metrics()
            await self.collect_node_metrics()
            await asyncio.sleep(interval)

# Start Prometheus metrics server
if __name__ == "__main__":
    start_http_server(9100)
    
    # Initialize MCP client and metrics
    mcp_client = ProxmoxMCPClient("http://localhost:8080")
    metrics = ProxmoxMCPMetrics(mcp_client)
    
    # Start collection
    asyncio.run(metrics.start_collection())
```

### Grafana Dashboard

**Dashboard JSON:**
```json
{
  "dashboard": {
    "title": "Proxmox MCP Monitoring",
    "panels": [
      {
        "title": "VM Status Overview",
        "type": "stat",
        "targets": [
          {
            "expr": "sum by(status) (proxmox_vms_total)",
            "legendFormat": "{{status}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 80},
                {"color": "red", "value": 90}
              ]
            }
          }
        }
      },
      {
        "title": "MCP Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(proxmox_mcp_requests_total[5m])",
            "legendFormat": "{{method}} - {{status}}"
          }
        ]
      },
      {
        "title": "Node Resource Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "proxmox_node_resources",
            "legendFormat": "{{node}} - {{resource}}"
          }
        ]
      }
    ]
  }
}
```

---

## Security Integration

### SIEM Integration

**Elastic Security Integration:**
```yaml
# elastic-agent.yml
inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/sudo-claude-user.log
      - /var/log/proxmox-mcp-security.log
    processors:
      - add_fields:
          target: ""
          fields:
            service: proxmox-mcp
            environment: production
            component: security
      - decode_json_fields:
          fields: ["message"]
          target: ""

outputs:
  elasticsearch:
    hosts: ["elasticsearch:9200"]
    index: "proxmox-mcp-security-%{+yyyy.MM.dd}"
    pipeline: proxmox-mcp-security
```

**Security Rules:**
```json
{
  "rule": {
    "name": "Proxmox MCP Suspicious Activity",
    "description": "Detect suspicious activity in Proxmox MCP",
    "query": {
      "bool": {
        "should": [
          {
            "match": {
              "message": "command not allowed"
            }
          },
          {
            "match": {
              "message": "authentication failure"
            }
          },
          {
            "range": {
              "@timestamp": {
                "gte": "now-5m"
              }
            }
          }
        ],
        "minimum_should_match": 2
      }
    },
    "actions": [
      {
        "email": {
          "to": "security@company.com",
          "subject": "Proxmox MCP Security Alert"
        }
      }
    ]
  }
}
```

### Vulnerability Scanning Integration

**Automated Security Scanning:**
```bash
#!/bin/bash
# security-scan.sh

echo "Running security scan for Proxmox MCP..."

# Container vulnerability scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image proxmox-mcp-server:latest \
  --format json --output /tmp/trivy-report.json

# Configuration security scan
docker run --rm -v /opt/proxmox-mcp:/config:ro \
  aquasec/trivy config /config \
  --format json --output /tmp/config-scan.json

# Security validation
sudo -u claude-user ./comprehensive-security-validation.sh \
  --json-output > /tmp/security-validation.json

# Combine reports
python3 << 'EOF'
import json
import sys

reports = {
    "vulnerability_scan": "/tmp/trivy-report.json",
    "config_scan": "/tmp/config-scan.json", 
    "security_validation": "/tmp/security-validation.json"
}

combined_report = {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "scan_type": "comprehensive_security",
    "reports": {}
}

for name, file_path in reports.items():
    try:
        with open(file_path, 'r') as f:
            combined_report["reports"][name] = json.load(f)
    except Exception as e:
        combined_report["reports"][name] = {"error": str(e)}

print(json.dumps(combined_report, indent=2))
EOF
```

---

## Custom Integrations

### Terraform Integration

**Terraform Provider Example:**
```hcl
# main.tf
terraform {
  required_providers {
    proxmox-mcp = {
      source = "local/proxmox-mcp"
      version = "1.0.0"
    }
  }
}

provider "proxmox-mcp" {
  endpoint = "http://192.168.1.137:8080/api/mcp"
  timeout  = 60
}

resource "proxmox-mcp_vm" "web_server" {
  name = "web-server-01"
  node = "proxmox"
  
  cpu = {
    cores = 2
    sockets = 1
  }
  
  memory = 4096
  
  disk = {
    size = "20G"
    storage = "local-lvm"
  }
  
  network = {
    bridge = "vmbr0"
    model = "virtio"
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

output "vm_status" {
  value = proxmox-mcp_vm.web_server.status
}
```

### Ansible Integration

**Ansible Playbook:**
```yaml
# proxmox-mcp.yml
---
- name: Manage Proxmox VMs via MCP
  hosts: localhost
  gather_facts: false
  
  vars:
    mcp_endpoint: "http://192.168.1.137:8080/api/mcp"
    
  tasks:
    - name: List all VMs
      uri:
        url: "{{ mcp_endpoint }}"
        method: POST
        headers:
          Content-Type: "application/json"
        body: |
          {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
              "name": "list_vms",
              "arguments": {}
            },
            "id": "ansible"
          }
        body_format: json
      register: vm_list_result
    
    - name: Display VM count
      debug:
        msg: "Found {{ vm_list_result.json.result | length }} VMs"
    
    - name: Start specific VM
      uri:
        url: "{{ mcp_endpoint }}"
        method: POST
        headers:
          Content-Type: "application/json"
        body: |
          {
            "jsonrpc": "2.0",
            "method": "tools/call", 
            "params": {
              "name": "vm_action",
              "arguments": {
                "vmid": {{ vm_id }},
                "node": "{{ vm_node }}",
                "action": "start"
              }
            },
            "id": "ansible"
          }
        body_format: json
      when: vm_id is defined and vm_node is defined
      register: vm_start_result
    
    - name: Wait for VM to be running
      uri:
        url: "{{ mcp_endpoint }}"
        method: POST
        headers:
          Content-Type: "application/json"
        body: |
          {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
              "name": "vm_status",
              "arguments": {
                "vmid": {{ vm_id }},
                "node": "{{ vm_node }}"
              }
            },
            "id": "ansible"
          }
        body_format: json
      register: vm_status_result
      until: vm_status_result.json.result.status.status == "running"
      retries: 30
      delay: 10
      when: vm_id is defined and vm_node is defined
```

### CI/CD Integration

**GitLab CI Integration:**
```yaml
# .gitlab-ci.yml
stages:
  - test
  - deploy
  - verify

variables:
  MCP_ENDPOINT: "http://192.168.1.137:8080/api/mcp"

test_mcp_connection:
  stage: test
  script:
    - curl -f "$MCP_ENDPOINT/../health" || exit 1
    - |
      curl -X POST "$MCP_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"ci"}' | \
        jq -e '.result.tools | length > 0' || exit 1
  only:
    - main
    - develop

deploy_vm:
  stage: deploy
  script:
    - |
      VM_RESULT=$(curl -X POST "$MCP_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d '{
          "jsonrpc": "2.0",
          "method": "tools/call",
          "params": {
            "name": "vm_action",
            "arguments": {
              "vmid": '$CI_VM_ID',
              "node": "'$CI_VM_NODE'",
              "action": "start"
            }
          },
          "id": "ci"
        }')
      echo "$VM_RESULT" | jq -e '.result' || exit 1
  environment:
    name: production
    url: http://vm-$CI_VM_ID.company.com
  only:
    - main

verify_deployment:
  stage: verify
  script:
    - sleep 30  # Wait for VM to start
    - |
      STATUS_RESULT=$(curl -X POST "$MCP_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d '{
          "jsonrpc": "2.0", 
          "method": "tools/call",
          "params": {
            "name": "vm_status",
            "arguments": {
              "vmid": '$CI_VM_ID',
              "node": "'$CI_VM_NODE'"
            }
          },
          "id": "ci"
        }')
      echo "$STATUS_RESULT" | jq -e '.result.status.status == "running"' || exit 1
  only:
    - main
```

---

## Integration Testing

### Automated Integration Tests

**Python Test Suite:**
```python
# test_integration.py
import pytest
import asyncio
import json
from proxmox_mcp_client import ProxmoxMCPClient

class TestProxmoxMCPIntegration:
    
    @pytest.fixture
    def mcp_client(self):
        return ProxmoxMCPClient("http://localhost:8080")
    
    @pytest.mark.asyncio
    async def test_health_endpoint(self, mcp_client):
        """Test health endpoint accessibility"""
        health_url = f"{mcp_client.base_url}/health"
        response = await mcp_client.session.get(health_url)
        assert response.status_code == 200
        
        health_data = response.json()
        assert health_data["status"] == "healthy"
    
    @pytest.mark.asyncio
    async def test_tools_list(self, mcp_client):
        """Test MCP tools list"""
        tools = await mcp_client.list_tools()
        assert len(tools) > 0
        
        expected_tools = [
            "execute_command", "list_vms", "vm_status", 
            "vm_action", "node_status", "proxmox_api"
        ]
        
        tool_names = [tool["name"] for tool in tools]
        for expected_tool in expected_tools:
            assert expected_tool in tool_names
    
    @pytest.mark.asyncio
    async def test_vm_operations(self, mcp_client):
        """Test VM operations"""
        # List VMs
        vms = await mcp_client.list_vms()
        assert isinstance(vms, list)
        
        if len(vms) > 0:
            vm = vms[0]
            vmid = vm["vmid"]
            node = vm["node"]
            
            # Get VM status
            status = await mcp_client.vm_status(vmid, node)
            assert "status" in status
            assert "config" in status
    
    @pytest.mark.asyncio
    async def test_command_execution(self, mcp_client):
        """Test command execution"""
        result = await mcp_client.execute_command("echo 'test'")
        assert isinstance(result, dict)
        assert "stdout" in result
        assert "test" in result["stdout"]
    
    @pytest.mark.asyncio
    async def test_error_handling(self, mcp_client):
        """Test error handling"""
        with pytest.raises(Exception):
            await mcp_client.vm_status(99999, "nonexistent")
    
    @pytest.mark.asyncio
    async def test_concurrent_requests(self, mcp_client):
        """Test concurrent request handling"""
        tasks = []
        for _ in range(10):
            tasks.append(mcp_client.list_tools())
        
        results = await asyncio.gather(*tasks)
        assert len(results) == 10
        
        # All results should be the same
        first_result = results[0]
        for result in results[1:]:
            assert result == first_result

# Load Testing
class TestLoadHandling:
    
    @pytest.mark.asyncio
    async def test_high_request_volume(self, mcp_client):
        """Test handling high request volume"""
        request_count = 100
        tasks = []
        
        for i in range(request_count):
            tasks.append(mcp_client.execute_command(f"echo 'request_{i}'"))
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Check that most requests succeeded
        successful_requests = [r for r in results if not isinstance(r, Exception)]
        success_rate = len(successful_requests) / request_count
        
        assert success_rate >= 0.95  # At least 95% success rate

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
```

**Test Configuration:**
```bash
#!/bin/bash
# run-integration-tests.sh

echo "Starting Proxmox MCP integration tests..."

# Start test environment
docker-compose -f docker-compose.test.yml up -d

# Wait for services
sleep 30

# Run tests
python -m pytest test_integration.py -v --tb=short

# Cleanup
docker-compose -f docker-compose.test.yml down

echo "Integration tests completed"
```

### End-to-End Testing

**E2E Test Script:**
```bash
#!/bin/bash
# e2e-test.sh

set -e

echo "=== END-TO-END INTEGRATION TEST ==="

MCP_URL="http://192.168.1.137:8080"
CLAUDE_CONFIG="$HOME/.claude.test.json"

# 1. Test MCP server health
echo "1. Testing MCP server health..."
if curl -f "$MCP_URL/health" | grep -q "healthy"; then
    echo "✅ MCP server is healthy"
else
    echo "❌ MCP server health check failed"
    exit 1
fi

# 2. Test Claude Code configuration
echo "2. Testing Claude Code configuration..."
cat > "$CLAUDE_CONFIG" << EOF
{
  "mcpServers": {
    "proxmox-test": {
      "type": "http",
      "url": "$MCP_URL/api/mcp",
      "name": "Proxmox Test"
    }
  }
}
EOF

if python3 -m json.tool "$CLAUDE_CONFIG" >/dev/null; then
    echo "✅ Claude configuration is valid"
else
    echo "❌ Claude configuration is invalid"
    exit 1
fi

# 3. Test MCP tool availability
echo "3. Testing MCP tool availability..."
tools_response=$(curl -s -X POST "$MCP_URL/api/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":"e2e"}')

if echo "$tools_response" | jq -e '.result.tools | length > 0' >/dev/null; then
    tool_count=$(echo "$tools_response" | jq '.result.tools | length')
    echo "✅ $tool_count MCP tools available"
else
    echo "❌ No MCP tools available"
    exit 1
fi

# 4. Test VM listing
echo "4. Testing VM operations..."
vm_response=$(curl -s -X POST "$MCP_URL/api/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_vms","arguments":{}},"id":"e2e"}')

if echo "$vm_response" | jq -e '.result' >/dev/null; then
    vm_count=$(echo "$vm_response" | jq '.result | length')
    echo "✅ VM listing successful ($vm_count VMs found)"
else
    echo "❌ VM listing failed"
    exit 1
fi

# 5. Test command execution
echo "5. Testing command execution..."
cmd_response=$(curl -s -X POST "$MCP_URL/api/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"execute_command","arguments":{"command":"whoami"}},"id":"e2e"}')

if echo "$cmd_response" | jq -e '.result' >/dev/null; then
    echo "✅ Command execution successful"
else
    echo "❌ Command execution failed"
    exit 1
fi

# 6. Test security validation
echo "6. Testing security validation..."
if sudo -u claude-user ./comprehensive-security-validation.sh --brief >/dev/null; then
    echo "✅ Security validation passed"
else
    echo "❌ Security validation failed"
    exit 1
fi

# Cleanup
rm -f "$CLAUDE_CONFIG"

echo ""
echo "🎉 ALL E2E TESTS PASSED!"
echo "Proxmox MCP integration is working correctly"
```

---

**Integration Success Criteria:**

✅ **Claude Code Integration**: MCP tools visible and functional  
✅ **API Integration**: REST/HTTP clients can interact with MCP  
✅ **Monitoring Integration**: Metrics and logs properly collected  
✅ **Security Integration**: SIEM and security tools receive events  
✅ **Enterprise Integration**: SSO, RBAC, and compliance features working  
✅ **Custom Integration**: Third-party tools and systems connected  

The Proxmox MCP system provides comprehensive integration capabilities for diverse environments and use cases.