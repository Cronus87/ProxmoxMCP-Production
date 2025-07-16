#!/usr/bin/env python3
"""
Security Middleware for Proxmox MCP Server
Provides authentication, authorization, and network restriction middleware
"""

import logging
import time
import ipaddress
from typing import Optional, List, Callable, Dict
from fastapi import Request, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import JSONResponse
import asyncio
from functools import wraps

from device_auth import DeviceAuthManager

logger = logging.getLogger(__name__)

class SecurityMiddleware:
    """Security middleware for authentication and authorization"""
    
    def __init__(self, device_auth_manager: DeviceAuthManager):
        self.device_auth_manager = device_auth_manager
        self.security = HTTPBearer(auto_error=False)
        
        # Rate limiting storage
        self.rate_limits = {}
        
        # Local network configuration
        self.local_networks = [
            ipaddress.ip_network('10.0.0.0/8'),
            ipaddress.ip_network('172.16.0.0/12'),
            ipaddress.ip_network('192.168.0.0/16'),
            ipaddress.ip_network('127.0.0.0/8'),
        ]
    
    def _get_client_ip(self, request: Request) -> str:
        """Extract client IP address from request"""
        # Check for forwarded headers (if behind proxy)
        forwarded_for = request.headers.get('X-Forwarded-For')
        if forwarded_for:
            # Take the first IP in the chain
            return forwarded_for.split(',')[0].strip()
        
        real_ip = request.headers.get('X-Real-IP')
        if real_ip:
            return real_ip
        
        # Fall back to direct connection
        if hasattr(request.client, 'host'):
            return request.client.host
        
        return '127.0.0.1'  # Default fallback
    
    def _is_local_network(self, ip_address: str) -> bool:
        """Check if IP address is from local network"""
        try:
            ip = ipaddress.ip_address(ip_address)
            return any(ip in network for network in self.local_networks)
        except:
            logger.warning(f"Invalid IP address format: {ip_address}")
            return False
    
    def _check_rate_limit(self, key: str, max_requests: int = 60, window_seconds: int = 60) -> bool:
        """Check rate limit for a given key"""
        current_time = time.time()
        window_start = current_time - window_seconds
        
        if key not in self.rate_limits:
            self.rate_limits[key] = []
        
        # Remove old requests outside the window
        self.rate_limits[key] = [
            req_time for req_time in self.rate_limits[key] 
            if req_time > window_start
        ]
        
        # Check if under limit
        if len(self.rate_limits[key]) >= max_requests:
            return False
        
        # Add current request
        self.rate_limits[key].append(current_time)
        return True
    
    async def authenticate_device_token(self, request: Request) -> Optional[Dict]:
        """Authenticate device using bearer token"""
        try:
            # Extract bearer token
            credentials: HTTPAuthorizationCredentials = await self.security(request)
            
            if not credentials:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Authentication required",
                    headers={"WWW-Authenticate": "Bearer"}
                )
            
            # Validate token
            client_ip = self._get_client_ip(request)
            is_valid, device_info, message = await self.device_auth_manager.validate_token(
                credentials.credentials, client_ip
            )
            
            if not is_valid:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Authentication failed: {message}",
                    headers={"WWW-Authenticate": "Bearer"}
                )
            
            # Add client IP to device info
            device_info['current_ip'] = client_ip
            
            return device_info
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Authentication error: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Authentication service error"
            )
    
    def require_device_auth(self, permissions: List[str] = None):
        """Decorator to require device authentication for endpoints"""
        def decorator(func: Callable):
            @wraps(func)
            async def wrapper(request: Request, *args, **kwargs):
                # Authenticate device
                device_info = await self.authenticate_device_token(request)
                
                # Check permissions if specified
                if permissions:
                    device_permissions = device_info.get('permissions', [])
                    missing_permissions = [p for p in permissions if p not in device_permissions]
                    
                    if missing_permissions:
                        raise HTTPException(
                            status_code=status.HTTP_403_FORBIDDEN,
                            detail=f"Missing required permissions: {', '.join(missing_permissions)}"
                        )
                
                # Add device info to request state
                request.state.device_info = device_info
                
                return await func(request, *args, **kwargs)
            return wrapper
        return decorator
    
    def require_local_network(self):
        """Decorator to restrict access to local network only"""
        def decorator(func: Callable):
            @wraps(func)
            async def wrapper(request: Request, *args, **kwargs):
                client_ip = self._get_client_ip(request)
                
                if not self._is_local_network(client_ip):
                    logger.warning(f"Non-local access attempt from {client_ip}")
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Access restricted to local network only"
                    )
                
                return await func(request, *args, **kwargs)
            return wrapper
        return decorator
    
    def rate_limit(self, max_requests: int = 60, window_seconds: int = 60, per_ip: bool = True):
        """Decorator for rate limiting"""
        def decorator(func: Callable):
            @wraps(func)
            async def wrapper(request: Request, *args, **kwargs):
                # Determine rate limit key
                if per_ip:
                    client_ip = self._get_client_ip(request)
                    rate_key = f"ip:{client_ip}"
                else:
                    rate_key = f"global:{func.__name__}"
                
                # Check rate limit
                if not self._check_rate_limit(rate_key, max_requests, window_seconds):
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Rate limit exceeded. Please try again later.",
                        headers={"Retry-After": str(window_seconds)}
                    )
                
                return await func(request, *args, **kwargs)
            return wrapper
        return decorator

class SecurityMiddlewareFactory:
    """Factory for creating configured security middleware instances"""
    
    @staticmethod
    def create_mcp_security(device_auth_manager: DeviceAuthManager) -> SecurityMiddleware:
        """Create security middleware for MCP endpoints"""
        return SecurityMiddleware(device_auth_manager)
    
    @staticmethod
    def create_admin_security(device_auth_manager: DeviceAuthManager) -> SecurityMiddleware:
        """Create security middleware for admin endpoints"""
        return SecurityMiddleware(device_auth_manager)

# Global exception handlers
async def authentication_exception_handler(request: Request, exc: HTTPException):
    """Handle authentication exceptions with proper logging"""
    client_ip = request.client.host if hasattr(request.client, 'host') else 'unknown'
    logger.warning(f"Authentication failed for {client_ip}: {exc.detail}")
    
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": "Authentication Failed",
            "detail": exc.detail,
            "type": "authentication_error"
        }
    )

async def authorization_exception_handler(request: Request, exc: HTTPException):
    """Handle authorization exceptions with proper logging"""
    client_ip = request.client.host if hasattr(request.client, 'host') else 'unknown'
    logger.warning(f"Authorization failed for {client_ip}: {exc.detail}")
    
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": "Access Denied",
            "detail": exc.detail,
            "type": "authorization_error"
        }
    )

async def rate_limit_exception_handler(request: Request, exc: HTTPException):
    """Handle rate limit exceptions with proper logging"""
    client_ip = request.client.host if hasattr(request.client, 'host') else 'unknown'
    logger.warning(f"Rate limit exceeded for {client_ip}")
    
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": "Rate Limit Exceeded",
            "detail": exc.detail,
            "type": "rate_limit_error",
            "retry_after": exc.headers.get("Retry-After", "60")
        }
    )