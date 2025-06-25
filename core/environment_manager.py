#!/usr/bin/env python3
"""
Environment Manager for Full Proxmox MCP Server
Handles environment detection and cross-platform path resolution
"""

import os
import sys
import platform
import subprocess
from pathlib import Path, PurePath, PureWindowsPath, PurePosixPath
from typing import Optional, Union, Dict, Any
import logging

logger = logging.getLogger(__name__)

class EnvironmentType:
    WINDOWS = "windows"
    WSL1 = "wsl1"
    WSL2 = "wsl2"
    LINUX = "linux"
    MACOS = "macos"
    UNKNOWN = "unknown"

class EnvironmentManager:
    """Manages environment detection and cross-platform compatibility"""
    
    def __init__(self):
        self._env_type = None
        self._windows_drive_mappings = {}
        self._detect_environment()
    
    def _detect_environment(self) -> None:
        """Detect the current environment type"""
        system = platform.system().lower()
        
        if system == "windows":
            self._env_type = EnvironmentType.WINDOWS
        elif system == "darwin":
            self._env_type = EnvironmentType.MACOS
        elif system == "linux":
            # Check if we're running in WSL
            if self._is_wsl():
                self._env_type = self._detect_wsl_version()
                self._map_windows_drives()
            else:
                self._env_type = EnvironmentType.LINUX
        else:
            self._env_type = EnvironmentType.UNKNOWN
            
        logger.info(f"Detected environment: {self._env_type}")
    
    def _is_wsl(self) -> bool:
        """Check if running in Windows Subsystem for Linux"""
        try:
            # Check for WSL-specific files/directories
            wsl_indicators = [
                "/proc/version",
                "/proc/sys/fs/binfmt_misc/WSLInterop"
            ]
            
            for indicator in wsl_indicators:
                if os.path.exists(indicator):
                    if indicator == "/proc/version":
                        with open(indicator, 'r') as f:
                            content = f.read().lower()
                            if "microsoft" in content or "wsl" in content:
                                return True
                    else:
                        return True
            
            # Check for WSL environment variables
            if os.getenv("WSL_DISTRO_NAME") or os.getenv("WSLENV"):
                return True
                
            return False
        except Exception:
            return False
    
    def _detect_wsl_version(self) -> str:
        """Detect WSL version (1 or 2)"""
        try:
            # WSL2 typically has different kernel version patterns
            with open("/proc/version", 'r') as f:
                version_info = f.read().lower()
                if "wsl2" in version_info:
                    return EnvironmentType.WSL2
                elif "microsoft" in version_info:
                    return EnvironmentType.WSL1
            return EnvironmentType.WSL2  # Default to WSL2 for newer installations
        except Exception:
            return EnvironmentType.WSL2
    
    def _map_windows_drives(self) -> None:
        """Map Windows drives available in WSL"""
        try:
            if os.path.exists("/mnt"):
                for drive in os.listdir("/mnt"):
                    if len(drive) == 1 and drive.isalpha():
                        wsl_path = f"/mnt/{drive.lower()}"
                        windows_path = f"{drive.upper()}:\\"
                        if os.path.exists(wsl_path):
                            self._windows_drive_mappings[windows_path] = wsl_path
                            self._windows_drive_mappings[f"{drive.upper()}:"] = f"/mnt/{drive.lower()}"
        except Exception as e:
            logger.warning(f"Failed to map Windows drives: {e}")
    
    @property
    def environment_type(self) -> str:
        """Get the detected environment type"""
        return self._env_type
    
    @property
    def is_windows(self) -> bool:
        """Check if running on Windows"""
        return self._env_type == EnvironmentType.WINDOWS
    
    @property
    def is_wsl(self) -> bool:
        """Check if running in WSL"""
        return self._env_type in [EnvironmentType.WSL1, EnvironmentType.WSL2]
    
    @property
    def is_linux(self) -> bool:
        """Check if running on native Linux"""
        return self._env_type == EnvironmentType.LINUX
    
    @property
    def is_macos(self) -> bool:
        """Check if running on macOS"""
        return self._env_type == EnvironmentType.MACOS
    
    def resolve_path(self, path: Union[str, Path], target_env: Optional[str] = None) -> str:
        """
        Resolve path for the target environment
        
        Args:
            path: Input path (can be Windows, WSL, or Unix format)
            target_env: Target environment ('windows', 'wsl', 'unix'), defaults to current
            
        Returns:
            Resolved path as string
        """
        if not path:
            return ""
            
        path_str = str(path)
        target_env = target_env or self._env_type
        
        # Normalize the path first
        normalized_path = self._normalize_path(path_str)
        
        # Convert based on target environment
        if target_env == EnvironmentType.WINDOWS:
            return self._to_windows_path(normalized_path)
        elif target_env in [EnvironmentType.WSL1, EnvironmentType.WSL2]:
            return self._to_wsl_path(normalized_path)
        else:
            return self._to_unix_path(normalized_path)
    
    def _normalize_path(self, path: str) -> str:
        """Normalize path separators and handle special cases"""
        # Replace backslashes with forward slashes for consistent processing
        path = path.replace("\\", "/")
        
        # Handle UNC paths or network paths
        if path.startswith("//"):
            return path
            
        return path
    
    def _to_windows_path(self, path: str) -> str:
        """Convert path to Windows format"""
        # If already a Windows path, return as-is
        if len(path) >= 2 and path[1] == ":":
            return path.replace("/", "\\")
        
        # Convert WSL path to Windows path
        if path.startswith("/mnt/"):
            # Extract drive letter and remaining path
            parts = path.split("/", 3)
            if len(parts) >= 3 and len(parts[2]) == 1:
                drive = parts[2].upper()
                remaining = "/" + parts[3] if len(parts) > 3 else ""
                return f"{drive}:{remaining}".replace("/", "\\")
        
        # Handle other Unix-style paths (relative to current Windows working directory)
        if path.startswith("/"):
            # This is tricky - we'll assume it's relative to C: for now
            return f"C:{path}".replace("/", "\\")
        
        return path.replace("/", "\\")
    
    def _to_wsl_path(self, path: str) -> str:
        """Convert path to WSL format"""
        # If already a WSL path, return as-is
        if path.startswith("/mnt/") or not (len(path) >= 2 and path[1] == ":"):
            return path
        
        # Convert Windows path to WSL path
        if len(path) >= 2 and path[1] == ":":
            drive = path[0].lower()
            remaining = path[2:] if len(path) > 2 else ""
            return f"/mnt/{drive}{remaining}".replace("\\", "/")
        
        return path
    
    def _to_unix_path(self, path: str) -> str:
        """Convert path to Unix format"""
        return path.replace("\\", "/")
    
    def get_project_root(self) -> Path:
        """Get the project root directory"""
        # Find the directory containing this file and go up to project root
        current_file = Path(__file__).resolve()
        # Go up from core/ to project root
        project_root = current_file.parent.parent
        return project_root
    
    def resolve_ssh_key_path(self, key_path: str) -> str:
        """Resolve SSH key path relative to project root"""
        if not key_path:
            return ""
        
        # If absolute path, resolve it
        if os.path.isabs(key_path):
            return self.resolve_path(key_path)
        
        # If relative path, make it relative to project root
        project_root = self.get_project_root()
        full_path = project_root / key_path
        return self.resolve_path(str(full_path))
    
    def get_python_executable(self, target_env: Optional[str] = None) -> str:
        """Get the appropriate Python executable path for the target environment"""
        target_env = target_env or self._env_type
        current_python = sys.executable
        
        if target_env == EnvironmentType.WINDOWS and self.is_wsl:
            # Convert WSL Python path to Windows path
            return self.resolve_path(current_python, EnvironmentType.WINDOWS)
        elif target_env in [EnvironmentType.WSL1, EnvironmentType.WSL2] and self.is_windows:
            # This is trickier - would need to know the WSL Python path
            # For now, return the current path and let the user configure
            return current_python
        
        return current_python
    
    def create_config_for_environment(self, base_config: Dict[str, Any], target_env: str) -> Dict[str, Any]:
        """Create configuration adapted for target environment"""
        config = base_config.copy()
        
        # Resolve all path-like configuration values
        path_keys = [
            "SSH_KEY_PATH", "ssh_key_path", "key_path",
            "LOG_FILE", "log_file", "config_file"
        ]
        
        for key in path_keys:
            if key in config and config[key]:
                config[key] = self.resolve_path(config[key], target_env)
        
        return config
    
    def get_environment_info(self) -> Dict[str, Any]:
        """Get detailed environment information for debugging"""
        return {
            "environment_type": self._env_type,
            "platform_system": platform.system(),
            "platform_release": platform.release(),
            "platform_version": platform.version(),
            "python_executable": sys.executable,
            "current_working_directory": os.getcwd(),
            "project_root": str(self.get_project_root()),
            "windows_drive_mappings": self._windows_drive_mappings,
            "environment_variables": {
                "WSL_DISTRO_NAME": os.getenv("WSL_DISTRO_NAME"),
                "WSLENV": os.getenv("WSLENV"),
                "PATH": os.getenv("PATH", "")[:200] + "..." if len(os.getenv("PATH", "")) > 200 else os.getenv("PATH", "")
            }
        }

# Global instance
env_manager = EnvironmentManager()