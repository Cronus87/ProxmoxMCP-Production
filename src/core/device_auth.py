#!/usr/bin/env python3
"""
Device Authentication System for Proxmox MCP Server
Provides secure device registration, token management, and validation
"""

import json
import secrets
import time
import uuid
import hashlib
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from enum import Enum
import ipaddress
import asyncio
import aiofiles

logger = logging.getLogger(__name__)

class DeviceStatus(Enum):
    """Device status enumeration"""
    PENDING = "pending"
    APPROVED = "approved"
    REVOKED = "revoked"
    EXPIRED = "expired"

@dataclass
class DeviceRequest:
    """Device registration request"""
    device_id: str
    device_name: str
    client_info: str
    ip_address: str
    user_agent: str
    requested_at: str
    status: str = DeviceStatus.PENDING.value
    approved_at: Optional[str] = None
    approved_by: str = "system"
    notes: str = ""

@dataclass
class DeviceToken:
    """Device authentication token"""
    device_id: str
    device_name: str
    token_hash: str
    ip_address: str
    created_at: str
    expires_at: str
    last_used_at: Optional[str] = None
    usage_count: int = 0
    status: str = DeviceStatus.APPROVED.value
    permissions: List[str] = None
    
    def __post_init__(self):
        if self.permissions is None:
            self.permissions = ["execute_command", "list_vms", "vm_status", "vm_action", "node_status", "proxmox_api"]

class DeviceAuthManager:
    """Manages device authentication, registration, and token validation"""
    
    def __init__(self, storage_dir: str = "/app/data"):
        self.storage_dir = Path(storage_dir)
        self.storage_dir.mkdir(parents=True, exist_ok=True)
        
        self.pending_requests_file = self.storage_dir / "pending_requests.json"
        self.approved_devices_file = self.storage_dir / "approved_devices.json"
        self.revoked_tokens_file = self.storage_dir / "revoked_tokens.json"
        
        # Rate limiting storage
        self.rate_limit_storage = {}
        
        # Token expiration settings
        self.default_token_expiry_days = 30
        self.max_token_expiry_days = 365
        
        # Initialize storage files
        asyncio.create_task(self._initialize_storage())
    
    async def _initialize_storage(self):
        """Initialize storage files if they don't exist"""
        try:
            # Ensure storage directory exists
            self.storage_dir.mkdir(parents=True, exist_ok=True)
            
            for file_path in [self.pending_requests_file, self.approved_devices_file, self.revoked_tokens_file]:
                if not file_path.exists():
                    async with aiofiles.open(file_path, 'w') as f:
                        await f.write('{}')
                    logger.debug(f"Created storage file: {file_path}")
            
            logger.info("Device authentication storage initialized")
        except Exception as e:
            logger.error(f"Failed to initialize storage: {e}")
            # Continue execution but log the error - storage will be created on demand
    
    def _generate_device_id(self) -> str:
        """Generate unique device ID"""
        return str(uuid.uuid4())
    
    def _generate_token(self) -> str:
        """Generate secure device token"""
        return secrets.token_urlsafe(64)
    
    def _hash_token(self, token: str) -> str:
        """Hash token for secure storage"""
        return hashlib.sha256(token.encode()).hexdigest()
    
    def _get_current_timestamp(self) -> str:
        """Get current timestamp as ISO string"""
        return datetime.now().isoformat()
    
    def _is_expired(self, expires_at: str) -> bool:
        """Check if timestamp is expired"""
        try:
            expiry_time = datetime.fromisoformat(expires_at)
            return datetime.now() > expiry_time
        except:
            return True
    
    async def _load_json_file(self, file_path: Path) -> Dict:
        """Load JSON file safely"""
        try:
            if file_path.exists():
                async with aiofiles.open(file_path, 'r') as f:
                    content = await f.read()
                    return json.loads(content) if content.strip() else {}
            return {}
        except Exception as e:
            logger.error(f"Error loading {file_path}: {e}")
            return {}
    
    async def _save_json_file(self, file_path: Path, data: Dict):
        """Save JSON file safely"""
        try:
            async with aiofiles.open(file_path, 'w') as f:
                await f.write(json.dumps(data, indent=2))
        except Exception as e:
            logger.error(f"Error saving {file_path}: {e}")
            raise
    
    def _check_rate_limit(self, ip_address: str, max_requests: int = 5, window_minutes: int = 15) -> bool:
        """Check if IP address is within rate limits"""
        current_time = time.time()
        window_start = current_time - (window_minutes * 60)
        
        if ip_address not in self.rate_limit_storage:
            self.rate_limit_storage[ip_address] = []
        
        # Remove old requests outside the window
        self.rate_limit_storage[ip_address] = [
            req_time for req_time in self.rate_limit_storage[ip_address] 
            if req_time > window_start
        ]
        
        # Check if under limit
        if len(self.rate_limit_storage[ip_address]) >= max_requests:
            return False
        
        # Add current request
        self.rate_limit_storage[ip_address].append(current_time)
        return True
    
    def _is_local_network(self, ip_address: str) -> bool:
        """Check if IP address is from local network"""
        try:
            ip = ipaddress.ip_address(ip_address)
            
            # Common local network ranges
            local_ranges = [
                ipaddress.ip_network('10.0.0.0/8'),
                ipaddress.ip_network('172.16.0.0/12'),
                ipaddress.ip_network('192.168.0.0/16'),
                ipaddress.ip_network('127.0.0.0/8'),
            ]
            
            return any(ip in network for network in local_ranges)
        except:
            return False
    
    async def request_device_registration(self, device_name: str, client_info: str, 
                                        ip_address: str, user_agent: str) -> Tuple[bool, str, Optional[str]]:
        """Request device registration"""
        try:
            # Rate limiting check
            if not self._check_rate_limit(ip_address):
                return False, "Rate limit exceeded. Please try again later.", None
            
            # Generate device ID
            device_id = self._generate_device_id()
            
            # Create device request
            device_request = DeviceRequest(
                device_id=device_id,
                device_name=device_name,
                client_info=client_info,
                ip_address=ip_address,
                user_agent=user_agent,
                requested_at=self._get_current_timestamp()
            )
            
            # Load existing requests
            pending_requests = await self._load_json_file(self.pending_requests_file)
            
            # Add new request
            pending_requests[device_id] = asdict(device_request)
            
            # Save requests
            await self._save_json_file(self.pending_requests_file, pending_requests)
            
            logger.info(f"Device registration requested: {device_name} ({device_id}) from {ip_address}")
            return True, "Device registration requested. Waiting for admin approval.", device_id
            
        except Exception as e:
            logger.error(f"Error requesting device registration: {e}")
            return False, f"Registration failed: {str(e)}", None
    
    async def approve_device(self, device_id: str, expiry_days: int = None) -> Tuple[bool, str, Optional[str]]:
        """Approve device registration and generate token"""
        try:
            if expiry_days is None:
                expiry_days = self.default_token_expiry_days
            
            if expiry_days > self.max_token_expiry_days:
                expiry_days = self.max_token_expiry_days
            
            # Load pending requests
            pending_requests = await self._load_json_file(self.pending_requests_file)
            
            if device_id not in pending_requests:
                return False, "Device request not found", None
            
            device_request = pending_requests[device_id]
            
            # Generate token
            token = self._generate_token()
            token_hash = self._hash_token(token)
            
            # Calculate expiry
            expires_at = (datetime.now() + timedelta(days=expiry_days)).isoformat()
            
            # Create device token
            device_token = DeviceToken(
                device_id=device_id,
                device_name=device_request['device_name'],
                token_hash=token_hash,
                ip_address=device_request['ip_address'],
                created_at=self._get_current_timestamp(),
                expires_at=expires_at
            )
            
            # Load approved devices
            approved_devices = await self._load_json_file(self.approved_devices_file)
            
            # Add approved device
            approved_devices[device_id] = asdict(device_token)
            
            # Save approved devices
            await self._save_json_file(self.approved_devices_file, approved_devices)
            
            # Remove from pending requests
            del pending_requests[device_id]
            await self._save_json_file(self.pending_requests_file, pending_requests)
            
            logger.info(f"Device approved: {device_request['device_name']} ({device_id})")
            return True, "Device approved successfully", token
            
        except Exception as e:
            logger.error(f"Error approving device: {e}")
            return False, f"Approval failed: {str(e)}", None
    
    async def revoke_device(self, device_id: str, reason: str = "Manual revocation") -> Tuple[bool, str]:
        """Revoke device access"""
        try:
            # Load approved devices
            approved_devices = await self._load_json_file(self.approved_devices_file)
            
            if device_id not in approved_devices:
                return False, "Device not found"
            
            device_token = approved_devices[device_id]
            device_token['status'] = DeviceStatus.REVOKED.value
            
            # Load revoked tokens
            revoked_tokens = await self._load_json_file(self.revoked_tokens_file)
            
            # Add to revoked list
            revoked_tokens[device_id] = {
                'device_name': device_token['device_name'],
                'token_hash': device_token['token_hash'],
                'revoked_at': self._get_current_timestamp(),
                'reason': reason
            }
            
            # Save changes
            await self._save_json_file(self.approved_devices_file, approved_devices)
            await self._save_json_file(self.revoked_tokens_file, revoked_tokens)
            
            logger.info(f"Device revoked: {device_token['device_name']} ({device_id})")
            return True, "Device access revoked successfully"
            
        except Exception as e:
            logger.error(f"Error revoking device: {e}")
            return False, f"Revocation failed: {str(e)}"
    
    async def validate_token(self, token: str, ip_address: str = None) -> Tuple[bool, Optional[Dict], str]:
        """Validate device token"""
        try:
            token_hash = self._hash_token(token)
            
            # Load approved devices
            approved_devices = await self._load_json_file(self.approved_devices_file)
            
            # Find device by token hash
            device_info = None
            device_id = None
            
            for d_id, device_data in approved_devices.items():
                if device_data.get('token_hash') == token_hash:
                    device_info = device_data
                    device_id = d_id
                    break
            
            if not device_info:
                return False, None, "Invalid token"
            
            # Check if device is revoked
            if device_info.get('status') == DeviceStatus.REVOKED.value:
                return False, None, "Device access has been revoked"
            
            # Check if token is expired
            if self._is_expired(device_info.get('expires_at', '')):
                # Mark as expired
                device_info['status'] = DeviceStatus.EXPIRED.value
                approved_devices[device_id] = device_info
                await self._save_json_file(self.approved_devices_file, approved_devices)
                return False, None, "Token has expired"
            
            # Update last used timestamp and usage count
            device_info['last_used_at'] = self._get_current_timestamp()
            device_info['usage_count'] = device_info.get('usage_count', 0) + 1
            
            # Save updated info
            approved_devices[device_id] = device_info
            await self._save_json_file(self.approved_devices_file, approved_devices)
            
            # Return device info without sensitive data
            safe_device_info = {
                'device_id': device_id,
                'device_name': device_info['device_name'],
                'permissions': device_info.get('permissions', []),
                'ip_address': device_info['ip_address'],
                'created_at': device_info['created_at'],
                'expires_at': device_info['expires_at'],
                'last_used_at': device_info['last_used_at'],
                'usage_count': device_info['usage_count']
            }
            
            return True, safe_device_info, "Token valid"
            
        except Exception as e:
            logger.error(f"Error validating token: {e}")
            return False, None, f"Validation failed: {str(e)}"
    
    async def get_pending_requests(self) -> List[Dict]:
        """Get list of pending device requests"""
        try:
            pending_requests = await self._load_json_file(self.pending_requests_file)
            return list(pending_requests.values())
        except Exception as e:
            logger.error(f"Error getting pending requests: {e}")
            return []
    
    async def get_approved_devices(self) -> List[Dict]:
        """Get list of approved devices"""
        try:
            approved_devices = await self._load_json_file(self.approved_devices_file)
            
            # Remove sensitive token information
            safe_devices = []
            for device_id, device_data in approved_devices.items():
                safe_device = {
                    'device_id': device_id,
                    'device_name': device_data['device_name'],
                    'ip_address': device_data['ip_address'],
                    'created_at': device_data['created_at'],
                    'expires_at': device_data['expires_at'],
                    'last_used_at': device_data.get('last_used_at'),
                    'usage_count': device_data.get('usage_count', 0),
                    'status': device_data.get('status', DeviceStatus.APPROVED.value),
                    'permissions': device_data.get('permissions', [])
                }
                safe_devices.append(safe_device)
            
            return safe_devices
        except Exception as e:
            logger.error(f"Error getting approved devices: {e}")
            return []
    
    async def cleanup_expired_tokens(self):
        """Clean up expired tokens"""
        try:
            approved_devices = await self._load_json_file(self.approved_devices_file)
            
            expired_count = 0
            for device_id, device_data in approved_devices.items():
                if self._is_expired(device_data.get('expires_at', '')):
                    device_data['status'] = DeviceStatus.EXPIRED.value
                    expired_count += 1
            
            if expired_count > 0:
                await self._save_json_file(self.approved_devices_file, approved_devices)
                logger.info(f"Marked {expired_count} tokens as expired")
            
        except Exception as e:
            logger.error(f"Error during token cleanup: {e}")
    
    async def get_system_stats(self) -> Dict:
        """Get system authentication statistics"""
        try:
            pending_requests = await self._load_json_file(self.pending_requests_file)
            approved_devices = await self._load_json_file(self.approved_devices_file)
            revoked_tokens = await self._load_json_file(self.revoked_tokens_file)
            
            # Count active vs expired devices
            active_count = 0
            expired_count = 0
            
            for device_data in approved_devices.values():
                if device_data.get('status') == DeviceStatus.EXPIRED.value or self._is_expired(device_data.get('expires_at', '')):
                    expired_count += 1
                elif device_data.get('status') == DeviceStatus.APPROVED.value:
                    active_count += 1
            
            return {
                'pending_requests': len(pending_requests),
                'active_devices': active_count,
                'expired_devices': expired_count,
                'revoked_devices': len(revoked_tokens),
                'total_devices': len(approved_devices)
            }
        except Exception as e:
            logger.error(f"Error getting system stats: {e}")
            return {
                'pending_requests': 0,
                'active_devices': 0,
                'expired_devices': 0,
                'revoked_devices': 0,
                'total_devices': 0
            }