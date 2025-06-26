#!/bin/bash

# PROXMOX MCP CONFIGURATION MANAGEMENT SYSTEM
# ===========================================
# Advanced configuration management for the master installation system
# Provides template-based configuration generation with validation
#
# FEATURES:
# - Auto-discovery of Proxmox environments
# - Template-based configuration generation
# - Multi-layer validation framework
# - Environment-specific optimizations
# - Backup and restore capabilities

set -euo pipefail

# ==============================================================================
# CONFIGURATION TEMPLATES AND SCHEMAS
# ==============================================================================

readonly TEMPLATES_DIR="$(dirname "$0")/templates"
readonly CONFIG_SCHEMA_DIR="$(dirname "$0")/schemas"

# Create templates directory if it doesn't exist
mkdir -p "$TEMPLATES_DIR" "$CONFIG_SCHEMA_DIR"

# ==============================================================================
# ENVIRONMENT DISCOVERY ENGINE
# ==============================================================================

discover_network_environment() {
    local discovery_results=()
    
    echo "🔍 Discovering network environment..."
    
    # Get local network information
    local local_ip=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    local network_prefix=$(echo "$local_ip" | sed 's/\.[0-9]*$//')
    local subnet_mask=$(ip route | grep "$local_ip" | awk '{print $1}' | head -1)
    
    echo "📍 Local IP: $local_ip"
    echo "📍 Network: $network_prefix.0/24"
    
    # Scan for Proxmox servers
    echo "🔍 Scanning for Proxmox servers..."
    local proxmox_servers=()
    
    for i in {1..254}; do
        local target_ip="${network_prefix}.${i}"
        if timeout 2 bash -c "echo >/dev/tcp/${target_ip}/8006" 2>/dev/null; then
            # Verify it's Proxmox by checking the web interface
            if curl -k -s --connect-timeout 3 "https://${target_ip}:8006" | grep -q -i "proxmox\|pve"; then
                proxmox_servers+=("$target_ip")
                echo "✅ Found Proxmox server: $target_ip"
                
                # Get additional information
                local version_info=""
                if version_response=$(curl -k -s --connect-timeout 3 "https://${target_ip}:8006/api2/json/version" 2>/dev/null); then
                    version_info=$(echo "$version_response" | jq -r '.data.version // "unknown"' 2>/dev/null || echo "unknown")
                fi
                
                discovery_results+=("$target_ip|$version_info")
            fi
        fi
    done
    
    # Scan for SSH services on discovered servers
    echo "🔍 Checking SSH accessibility..."
    for server_info in "${discovery_results[@]}"; do
        local server_ip=$(echo "$server_info" | cut -d'|' -f1)
        
        if timeout 2 bash -c "echo >/dev/tcp/${server_ip}/22" 2>/dev/null; then
            echo "✅ SSH accessible on $server_ip"
        else
            echo "⚠️  SSH not accessible on $server_ip"
        fi
    done
    
    # Output discovery results
    if [[ ${#discovery_results[@]} -gt 0 ]]; then
        echo ""
        echo "📊 Discovery Summary:"
        echo "===================="
        printf "%-15s %-15s %-10s\n" "IP Address" "Version" "SSH"
        echo "----------------------------------------"
        
        for server_info in "${discovery_results[@]}"; do
            local server_ip=$(echo "$server_info" | cut -d'|' -f1)
            local version=$(echo "$server_info" | cut -d'|' -f2)
            local ssh_status="❌"
            
            if timeout 2 bash -c "echo >/dev/tcp/${server_ip}/22" 2>/dev/null; then
                ssh_status="✅"
            fi
            
            printf "%-15s %-15s %-10s\n" "$server_ip" "$version" "$ssh_status"
        done
        
        # Export results for use by installer
        export DISCOVERED_PROXMOX_SERVERS="${discovery_results[*]}"
        export PRIMARY_PROXMOX_SERVER=$(echo "${discovery_results[0]}" | cut -d'|' -f1)
        
        return 0
    else
        echo "❌ No Proxmox servers discovered on local network"
        return 1
    fi
}

# ==============================================================================
# CONFIGURATION TEMPLATE SYSTEM
# ==============================================================================

create_environment_template() {
    cat > "$TEMPLATES_DIR/environment.template" << 'EOF'
# Proxmox MCP Production Configuration
# Generated from template by installer
# Timestamp: {{TIMESTAMP}}
# Installation ID: {{INSTALLATION_ID}}

# Container Configuration
IMAGE_TAG={{IMAGE_TAG}}
LOG_LEVEL={{LOG_LEVEL}}

# SSH Configuration
SSH_TARGET={{SSH_TARGET}}
SSH_HOST={{SSH_HOST}}
SSH_USER={{SSH_USER}}
SSH_PORT={{SSH_PORT}}
SSH_KEY_PATH={{SSH_KEY_PATH}}

# Proxmox API Configuration  
PROXMOX_HOST={{PROXMOX_HOST}}
PROXMOX_USER={{PROXMOX_USER}}
PROXMOX_TOKEN_NAME={{PROXMOX_TOKEN_NAME}}
PROXMOX_TOKEN_VALUE={{PROXMOX_TOKEN_VALUE}}
PROXMOX_VERIFY_SSL={{PROXMOX_VERIFY_SSL}}

# Feature Configuration
ENABLE_PROXMOX_API={{ENABLE_PROXMOX_API}}
ENABLE_DANGEROUS_COMMANDS={{ENABLE_DANGEROUS_COMMANDS}}

# MCP Server Configuration
MCP_HOST={{MCP_HOST}}
MCP_PORT={{MCP_PORT}}

# Security Configuration
SECURITY_LEVEL={{SECURITY_LEVEL}}
ENABLE_AUDIT_LOGGING={{ENABLE_AUDIT_LOGGING}}

# Monitoring Configuration
ENABLE_MONITORING={{ENABLE_MONITORING}}
GRAFANA_PASSWORD={{GRAFANA_PASSWORD}}
PROMETHEUS_RETENTION={{PROMETHEUS_RETENTION}}

# Network Configuration
EXTERNAL_ACCESS={{EXTERNAL_ACCESS}}
ALLOWED_NETWORKS={{ALLOWED_NETWORKS}}

# Backup Configuration
ENABLE_AUTOMATED_BACKUPS={{ENABLE_AUTOMATED_BACKUPS}}
BACKUP_RETENTION_DAYS={{BACKUP_RETENTION_DAYS}}
EOF
}

create_docker_compose_template() {
    cat > "$TEMPLATES_DIR/docker-compose.template" << 'EOF'
version: '3.8'

services:
  mcp-server:
    image: {{CONTAINER_IMAGE}}:{{IMAGE_TAG}}
    container_name: {{CONTAINER_PREFIX}}-server
    restart: unless-stopped
    ports:
      - "{{BIND_ADDRESS}}:{{MCP_PORT}}:8080"
    environment:
      - MCP_HOST={{MCP_HOST}}
      - MCP_PORT=8080
      - LOG_LEVEL={{LOG_LEVEL}}
      # SSH Configuration
      - SSH_TARGET={{SSH_TARGET}}
      - SSH_HOST={{SSH_HOST}}
      - SSH_USER={{SSH_USER}}
      - SSH_PORT={{SSH_PORT}}
      - SSH_KEY_PATH=/app/keys/ssh_key
      # Proxmox Configuration
      - PROXMOX_HOST={{PROXMOX_HOST}}
      - PROXMOX_USER={{PROXMOX_USER}}
      - PROXMOX_TOKEN_NAME={{PROXMOX_TOKEN_NAME}}
      - PROXMOX_TOKEN_VALUE={{PROXMOX_TOKEN_VALUE}}
      - PROXMOX_VERIFY_SSL={{PROXMOX_VERIFY_SSL}}
      - ENABLE_PROXMOX_API={{ENABLE_PROXMOX_API}}
      - ENABLE_DANGEROUS_COMMANDS={{ENABLE_DANGEROUS_COMMANDS}}
    volumes:
      - mcp_logs:/app/logs
      - {{INSTALL_ROOT}}/keys:/app/keys:ro
      - {{INSTALL_ROOT}}/config:/app/config:ro
    networks:
      - mcp-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '{{CPU_LIMIT}}'
          memory: {{MEMORY_LIMIT}}
        reservations:
          cpus: '{{CPU_RESERVATION}}'
          memory: {{MEMORY_RESERVATION}}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  caddy:
    image: caddy:2-alpine
    container_name: {{CONTAINER_PREFIX}}-proxy
    restart: unless-stopped
    ports:
      - "{{HTTP_PORT}}:80"
      - "{{HTTPS_PORT}}:443"
    volumes:
      - {{INSTALL_ROOT}}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - mcp-network
    depends_on:
      mcp-server:
        condition: service_healthy
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"

{{MONITORING_SERVICES}}

networks:
  mcp-network:
    driver: bridge
    name: {{NETWORK_NAME}}

volumes:
  mcp_logs:
    name: {{VOLUME_PREFIX}}_logs
  caddy_data:
    name: {{VOLUME_PREFIX}}_caddy_data
  caddy_config:
    name: {{VOLUME_PREFIX}}_caddy_config
{{MONITORING_VOLUMES}}
EOF
}

create_monitoring_services_template() {
    cat > "$TEMPLATES_DIR/monitoring-services.template" << 'EOF'
  
  # Monitoring Services
  prometheus:
    image: prom/prometheus:latest
    container_name: {{CONTAINER_PREFIX}}-prometheus
    restart: unless-stopped
    ports:
      - "{{BIND_ADDRESS}}:9090:9090"
    volumes:
      - {{INSTALL_ROOT}}/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - mcp-network
    profiles:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: {{CONTAINER_PREFIX}}-grafana
    restart: unless-stopped
    ports:
      - "{{BIND_ADDRESS}}:3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD={{GRAFANA_PASSWORD}}
      - GF_SECURITY_ADMIN_USER=admin
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_AUTH_ANONYMOUS_ENABLED=false
    volumes:
      - grafana_data:/var/lib/grafana
      - {{INSTALL_ROOT}}/monitoring/grafana:/etc/grafana/provisioning
    networks:
      - mcp-network
    profiles:
      - monitoring
EOF
}

create_monitoring_volumes_template() {
    cat > "$TEMPLATES_DIR/monitoring-volumes.template" << 'EOF'
  prometheus_data:
    name: {{VOLUME_PREFIX}}_prometheus_data
  grafana_data:
    name: {{VOLUME_PREFIX}}_grafana_data
EOF
}

create_caddy_template() {
    cat > "$TEMPLATES_DIR/Caddyfile.template" << 'EOF'
# Caddyfile for Proxmox MCP Server
# Generated from template
# Configuration: {{CONFIGURATION_TYPE}}

{{#DOMAIN_CONFIG}}
{{DOMAIN_NAME}} {
    reverse_proxy mcp-server:8080 {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    # Enable HTTP/2
    protocols h1 h2
    
    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "geolocation=(), microphone=(), camera=()"
    }
    
    # CORS headers for MCP clients
    header {
        Access-Control-Allow-Origin "{{CORS_ORIGINS}}"
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With"
    }
    
    # Handle OPTIONS requests for CORS
    @options {
        method OPTIONS
    }
    respond @options 204
    
    # Rate limiting
    rate_limit {
        zone mcp {
            key {remote_host}
            events {{RATE_LIMIT_REQUESTS}}
            window {{RATE_LIMIT_WINDOW}}
        }
    }
}
{{/DOMAIN_CONFIG}}

{{#LOCAL_CONFIG}}
# Local development/internal access
:{{HTTP_PORT}} {
    reverse_proxy mcp-server:8080
    
    # CORS headers for development
    header {
        Access-Control-Allow-Origin "*"
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With"
    }
    
    @options {
        method OPTIONS
    }
    respond @options 204
    
    # IP access restrictions
    @restricted {
        not remote_ip {{ALLOWED_NETWORKS}}
    }
    respond @restricted "Access Denied" 403
}
{{/LOCAL_CONFIG}}
EOF
}

# ==============================================================================
# CONFIGURATION VALIDATION SCHEMAS
# ==============================================================================

create_validation_schema() {
    cat > "$CONFIG_SCHEMA_DIR/config.schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Proxmox MCP Configuration Schema",
  "type": "object",
  "required": [
    "proxmox_host",
    "ssh_user",
    "proxmox_token_value"
  ],
  "properties": {
    "proxmox_host": {
      "type": "string",
      "pattern": "^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$|^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
      "description": "Proxmox server IP address or hostname"
    },
    "ssh_user": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9-]*$",
      "minLength": 3,
      "maxLength": 32,
      "description": "SSH username for MCP operations"
    },
    "ssh_port": {
      "type": "integer",
      "minimum": 1,
      "maximum": 65535,
      "default": 22
    },
    "proxmox_user": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9@.-]+$",
      "default": "root@pam"
    },
    "proxmox_token_name": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9-]+$",
      "default": "claude-mcp"
    },
    "proxmox_token_value": {
      "type": "string",
      "minLength": 32,
      "description": "Proxmox API token value"
    },
    "mcp_port": {
      "type": "integer",
      "minimum": 1024,
      "maximum": 65535,
      "default": 8080
    },
    "enable_monitoring": {
      "type": "boolean",
      "default": false
    },
    "security_level": {
      "type": "string",
      "enum": ["basic", "enhanced", "maximum"],
      "default": "enhanced"
    },
    "external_access": {
      "type": "boolean",
      "default": false
    },
    "domain_name": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
    }
  }
}
EOF
}

# ==============================================================================
# TEMPLATE PROCESSING ENGINE
# ==============================================================================

process_template() {
    local template_file="$1"
    local output_file="$2"
    local config_file="$3"
    
    if [[ ! -f "$template_file" ]]; then
        echo "❌ Template file not found: $template_file"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        echo "❌ Configuration file not found: $config_file"
        return 1
    fi
    
    echo "🔄 Processing template: $(basename "$template_file")"
    
    # Load configuration values
    local config_content
    config_content=$(cat "$config_file")
    
    # Simple template variable substitution
    local template_content
    template_content=$(cat "$template_file")
    
    # Replace template variables with values from config
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes from value
            value=$(echo "$value" | sed 's/^"//;s/"$//')
            
            # Replace {{KEY}} with value in template
            template_content="${template_content//\{\{${key}\}\}/$value}"
        fi
    done <<< "$config_content"
    
    # Handle conditional sections
    template_content=$(process_conditional_sections "$template_content" "$config_file")
    
    # Write processed template to output file
    echo "$template_content" > "$output_file"
    
    echo "✅ Template processed: $output_file"
}

process_conditional_sections() {
    local content="$1"
    local config_file="$2"
    
    # Process {{#MONITORING_ENABLED}} sections
    if grep -q "ENABLE_MONITORING=true" "$config_file"; then
        # Enable monitoring sections
        content=$(echo "$content" | sed '/{{#MONITORING_ENABLED}}/,/{{\/MONITORING_ENABLED}}/c\
{{MONITORING_SERVICES}}')
    else
        # Remove monitoring sections
        content=$(echo "$content" | sed '/{{#MONITORING_ENABLED}}/,/{{\/MONITORING_ENABLED}}/d')
    fi
    
    # Process {{#DOMAIN_CONFIG}} sections
    if grep -q "EXTERNAL_ACCESS=true" "$config_file"; then
        content=$(echo "$content" | sed 's/{{#DOMAIN_CONFIG}}//' | sed 's/{{\/DOMAIN_CONFIG}}//')
        content=$(echo "$content" | sed '/{{#LOCAL_CONFIG}}/,/{{\/LOCAL_CONFIG}}/d')
    else
        content=$(echo "$content" | sed '/{{#DOMAIN_CONFIG}}/,/{{\/DOMAIN_CONFIG}}/d')
        content=$(echo "$content" | sed 's/{{#LOCAL_CONFIG}}//' | sed 's/{{\/LOCAL_CONFIG}}//')
    fi
    
    echo "$content"
}

# ==============================================================================
# CONFIGURATION VALIDATION ENGINE
# ==============================================================================

validate_configuration() {
    local config_file="$1"
    local schema_file="$CONFIG_SCHEMA_DIR/config.schema.json"
    
    echo "🔍 Validating configuration..."
    
    if [[ ! -f "$config_file" ]]; then
        echo "❌ Configuration file not found: $config_file"
        return 1
    fi
    
    # Basic validation checks
    validate_required_parameters "$config_file"
    validate_network_parameters "$config_file"
    validate_security_parameters "$config_file"
    validate_resource_parameters "$config_file"
    
    echo "✅ Configuration validation completed"
}

validate_required_parameters() {
    local config_file="$1"
    local required_params=("PROXMOX_HOST" "SSH_USER" "PROXMOX_TOKEN_VALUE")
    
    for param in "${required_params[@]}"; do
        if ! grep -q "^${param}=" "$config_file"; then
            echo "❌ Required parameter missing: $param"
            return 1
        fi
        
        local value=$(grep "^${param}=" "$config_file" | cut -d'=' -f2 | tr -d '"')
        if [[ -z "$value" ]]; then
            echo "❌ Required parameter empty: $param"
            return 1
        fi
    done
    
    echo "✅ Required parameters validated"
}

validate_network_parameters() {
    local config_file="$1"
    
    # Validate IP address format
    local proxmox_host=$(grep "^PROXMOX_HOST=" "$config_file" | cut -d'=' -f2 | tr -d '"')
    if [[ "$proxmox_host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Validate IP octets
        IFS='.' read -r -a octets <<< "$proxmox_host"
        for octet in "${octets[@]}"; do
            if [[ "$octet" -gt 255 ]]; then
                echo "❌ Invalid IP address: $proxmox_host"
                return 1
            fi
        done
    fi
    
    # Validate port numbers
    local ports=("SSH_PORT" "MCP_PORT")
    for port_var in "${ports[@]}"; do
        if grep -q "^${port_var}=" "$config_file"; then
            local port=$(grep "^${port_var}=" "$config_file" | cut -d'=' -f2 | tr -d '"')
            if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
                echo "❌ Invalid port number for $port_var: $port"
                return 1
            fi
        fi
    done
    
    echo "✅ Network parameters validated"
}

validate_security_parameters() {
    local config_file="$1"
    
    # Validate SSH user format
    local ssh_user=$(grep "^SSH_USER=" "$config_file" | cut -d'=' -f2 | tr -d '"')
    if [[ ! "$ssh_user" =~ ^[a-z][a-z0-9-]*$ ]]; then
        echo "❌ Invalid SSH username format: $ssh_user"
        return 1
    fi
    
    # Check for common weak usernames
    local weak_users=("admin" "root" "user" "test" "guest")
    for weak_user in "${weak_users[@]}"; do
        if [[ "$ssh_user" == "$weak_user" ]]; then
            echo "⚠️  Warning: SSH username '$ssh_user' may be a security risk"
        fi
    done
    
    # Validate token format (basic check)
    local token_value=$(grep "^PROXMOX_TOKEN_VALUE=" "$config_file" | cut -d'=' -f2 | tr -d '"')
    if [[ ${#token_value} -lt 32 ]]; then
        echo "❌ Proxmox token appears too short (minimum 32 characters)"
        return 1
    fi
    
    echo "✅ Security parameters validated"
}

validate_resource_parameters() {
    local config_file="$1"
    
    # Validate memory limits if specified
    if grep -q "^MEMORY_LIMIT=" "$config_file"; then
        local memory_limit=$(grep "^MEMORY_LIMIT=" "$config_file" | cut -d'=' -f2 | tr -d '"')
        if [[ ! "$memory_limit" =~ ^[0-9]+[MGT]?$ ]]; then
            echo "❌ Invalid memory limit format: $memory_limit"
            return 1
        fi
    fi
    
    # Validate CPU limits if specified
    if grep -q "^CPU_LIMIT=" "$config_file"; then
        local cpu_limit=$(grep "^CPU_LIMIT=" "$config_file" | cut -d'=' -f2 | tr -d '"')
        if [[ ! "$cpu_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "❌ Invalid CPU limit format: $cpu_limit"
            return 1
        fi
    fi
    
    echo "✅ Resource parameters validated"
}

# ==============================================================================
# CONFIGURATION OPTIMIZATION ENGINE
# ==============================================================================

optimize_configuration() {
    local config_file="$1"
    local environment_type="$2" # development, staging, production
    
    echo "🔧 Optimizing configuration for environment: $environment_type"
    
    case "$environment_type" in
        "development")
            optimize_for_development "$config_file"
            ;;
        "staging")
            optimize_for_staging "$config_file"
            ;;
        "production")
            optimize_for_production "$config_file"
            ;;
        *)
            echo "⚠️  Unknown environment type: $environment_type"
            ;;
    esac
    
    echo "✅ Configuration optimization completed"
}

optimize_for_development() {
    local config_file="$1"
    
    # Development optimizations
    sed -i 's/LOG_LEVEL=.*/LOG_LEVEL=DEBUG/' "$config_file"
    sed -i 's/SECURITY_LEVEL=.*/SECURITY_LEVEL=basic/' "$config_file"
    sed -i 's/ENABLE_MONITORING=.*/ENABLE_MONITORING=true/' "$config_file"
    sed -i 's/CPU_LIMIT=.*/CPU_LIMIT=1.0/' "$config_file"
    sed -i 's/MEMORY_LIMIT=.*/MEMORY_LIMIT=1G/' "$config_file"
    
    echo "✅ Applied development optimizations"
}

optimize_for_staging() {
    local config_file="$1"
    
    # Staging optimizations
    sed -i 's/LOG_LEVEL=.*/LOG_LEVEL=INFO/' "$config_file"
    sed -i 's/SECURITY_LEVEL=.*/SECURITY_LEVEL=enhanced/' "$config_file"
    sed -i 's/ENABLE_MONITORING=.*/ENABLE_MONITORING=true/' "$config_file"
    sed -i 's/CPU_LIMIT=.*/CPU_LIMIT=1.5/' "$config_file"
    sed -i 's/MEMORY_LIMIT=.*/MEMORY_LIMIT=1.5G/' "$config_file"
    
    echo "✅ Applied staging optimizations"
}

optimize_for_production() {
    local config_file="$1"
    
    # Production optimizations
    sed -i 's/LOG_LEVEL=.*/LOG_LEVEL=WARNING/' "$config_file"
    sed -i 's/SECURITY_LEVEL=.*/SECURITY_LEVEL=maximum/' "$config_file"
    sed -i 's/ENABLE_MONITORING=.*/ENABLE_MONITORING=true/' "$config_file"
    sed -i 's/CPU_LIMIT=.*/CPU_LIMIT=2.0/' "$config_file"
    sed -i 's/MEMORY_LIMIT=.*/MEMORY_LIMIT=2G/' "$config_file"
    sed -i 's/ENABLE_DANGEROUS_COMMANDS=.*/ENABLE_DANGEROUS_COMMANDS=false/' "$config_file"
    
    echo "✅ Applied production optimizations"
}

# ==============================================================================
# MAIN CONFIGURATION MANAGEMENT FUNCTIONS
# ==============================================================================

initialize_templates() {
    echo "🔧 Initializing configuration templates..."
    
    mkdir -p "$TEMPLATES_DIR" "$CONFIG_SCHEMA_DIR"
    
    create_environment_template
    create_docker_compose_template
    create_monitoring_services_template
    create_monitoring_volumes_template
    create_caddy_template
    create_validation_schema
    
    echo "✅ Configuration templates initialized"
}

generate_configuration() {
    local install_root="$1"
    local config_params="$2"
    local environment_type="${3:-production}"
    
    echo "🔧 Generating configuration files..."
    
    # Ensure templates exist
    initialize_templates
    
    # Create configuration from parameters
    echo "$config_params" > "$install_root/config.env"
    
    # Optimize for environment
    optimize_configuration "$install_root/config.env" "$environment_type"
    
    # Validate configuration
    validate_configuration "$install_root/config.env"
    
    # Process templates
    process_template "$TEMPLATES_DIR/environment.template" "$install_root/.env" "$install_root/config.env"
    process_template "$TEMPLATES_DIR/docker-compose.template" "$install_root/docker-compose.yml" "$install_root/config.env"
    
    # Create Caddy configuration directory and file
    mkdir -p "$install_root/caddy"
    process_template "$TEMPLATES_DIR/Caddyfile.template" "$install_root/caddy/Caddyfile" "$install_root/config.env"
    
    echo "✅ Configuration files generated"
}

# ==============================================================================
# COMMAND LINE INTERFACE
# ==============================================================================

show_help() {
    cat << EOF
Proxmox MCP Configuration Manager

Usage: $0 [command] [options]

Commands:
  discover              Discover Proxmox servers on network
  init-templates        Initialize configuration templates
  generate CONFIG_FILE  Generate configuration from parameters
  validate CONFIG_FILE  Validate configuration file
  optimize CONFIG_FILE ENV_TYPE  Optimize for environment (dev/staging/prod)

Options:
  --help               Show this help message
  --version            Show version information

Examples:
  $0 discover
  $0 generate /opt/proxmox-mcp/config.env
  $0 validate /opt/proxmox-mcp/.env
  $0 optimize /opt/proxmox-mcp/.env production

EOF
}

main() {
    case "${1:-help}" in
        "discover")
            discover_network_environment
            ;;
        "init-templates")
            initialize_templates
            ;;
        "generate")
            if [[ -n "${2:-}" ]]; then
                generate_configuration "${2%/*}" "$(cat "${2}")" "${3:-production}"
            else
                echo "❌ Configuration file required"
                exit 1
            fi
            ;;
        "validate")
            if [[ -n "${2:-}" ]]; then
                validate_configuration "$2"
            else
                echo "❌ Configuration file required"
                exit 1
            fi
            ;;
        "optimize")
            if [[ -n "${2:-}" ]] && [[ -n "${3:-}" ]]; then
                optimize_configuration "$2" "$3"
            else
                echo "❌ Configuration file and environment type required"
                exit 1
            fi
            ;;
        "--help"|"help")
            show_help
            ;;
        "--version")
            echo "Proxmox MCP Configuration Manager v1.0.0"
            ;;
        *)
            echo "❌ Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi