# Contributing to Proxmox MCP

Thank you for your interest in contributing to Proxmox MCP! This guide will help you get started with development and contributions.

## Table of Contents
- [Development Setup](#development-setup)
- [Code Standards](#code-standards)
- [Documentation Standards](#documentation-standards)
- [Security Guidelines](#security-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)

## Development Setup

### Prerequisites
- Proxmox VE system for testing
- Docker and docker-compose
- Python 3.9+ with pip
- Git

### Local Development Environment

```bash
# Clone repository
git clone https://github.com/YOUR-ORG/ProxmoxMCP-Production.git
cd ProxmoxMCP-Production

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set up development environment variables
cp .env.template .env.development
# Edit .env.development with your Proxmox credentials

# Run development server
python src/main.py
```

### Project Structure

```
ProxmoxMCP-Production/
├── src/                    # Source code
│   ├── core/              # Core MCP server implementation
│   ├── main.py            # Application entry point
│   └── utils/             # Utility functions
├── scripts/               # Installation and deployment scripts
│   ├── install/           # Installation scripts
│   ├── deploy/            # Deployment automation
│   ├── security/          # Security validation
│   └── maintenance/       # System maintenance
├── config/                # Configuration files
│   ├── sudoers/           # User permission configurations
│   └── caddy/             # Reverse proxy configurations
├── docker/                # Container configurations
├── docs/                  # Documentation
└── tests/                 # Test files
```

## Code Standards

### Python Code Style
- **PEP 8 compliance** - Use black for formatting
- **Type hints** - Include type annotations for function parameters and returns
- **Docstrings** - Document all classes and functions
- **Error handling** - Comprehensive exception handling with logging

### Example Code Structure
```python
from typing import Dict, Optional
import logging

logger = logging.getLogger(__name__)

class ProxmoxMCPServer:
    """Main MCP server for Proxmox integration.
    
    Provides secure access to Proxmox VE functionality through
    the Model Context Protocol with enterprise security controls.
    """
    
    def __init__(self, config: Dict[str, str]) -> None:
        """Initialize MCP server with configuration.
        
        Args:
            config: Configuration dictionary with connection settings
            
        Raises:
            ConfigurationError: If required configuration is missing
        """
        self.config = config
        self._validate_config()
    
    async def execute_command(self, command: str, timeout: int = 30) -> Dict[str, str]:
        """Execute command via SSH with security validation.
        
        Args:
            command: Shell command to execute
            timeout: Command timeout in seconds
            
        Returns:
            Dictionary containing command output and metadata
            
        Raises:
            SecurityError: If command is not allowed
            ExecutionError: If command execution fails
        """
        try:
            # Security validation
            self._validate_command(command)
            
            # Execute command
            result = await self._ssh_execute(command, timeout)
            
            logger.info(f"Command executed successfully: {command[:50]}...")
            return result
            
        except Exception as e:
            logger.error(f"Command execution failed: {e}")
            raise
```

### Security-First Development
- **Input validation** - Validate all user inputs
- **Command filtering** - Whitelist approach for allowed operations
- **Audit logging** - Log all security-relevant operations
- **Principle of least privilege** - Minimal necessary permissions

## Documentation Standards

### User-First Approach
- Write for the end user, not the developer
- Include step-by-step instructions with expected outputs
- Provide copy-paste ready commands
- Cross-reference related sections

### Markdown Standards
```markdown
# Document Title (H1 - only one per document)

**Brief description of document purpose**

## Table of Contents
1. [Section Name](#section-name)
2. [Another Section](#another-section)

## Section Name

### Implementation Steps

**Step 1: Description**
```bash
# Command example with comments
sudo systemctl status proxmox-mcp
```

**Expected Output:**
```
● proxmox-mcp.service - Proxmox MCP HTTP Server
   Active: active (running)
```

**Important Notes:**
- ✅ Use for positive outcomes
- ❌ Use for problems  
- ⚠️ Use for warnings
- 💡 Use for tips
```

### Documentation Requirements
- **All features must be documented** before merge
- **Update relevant guides** when changing functionality
- **Include troubleshooting** for common issues
- **Maintain cross-references** between related documents

## Security Guidelines

### Critical Security Rules
1. **Never commit secrets** - No credentials, keys, or tokens in code
2. **Security review required** - All security-related changes need review
3. **Maintain compatibility** - Don't break existing security controls
4. **Document security implications** - Explain security impact of changes

### Security Changes Process
1. **Security analysis** - Document threat model impact
2. **Testing validation** - Run comprehensive security test suite
3. **Peer review** - Security team approval required
4. **Documentation** - Update security guides

### Command Security
All new sudo commands must be:
- **Explicitly allowed** in sudoers configuration
- **Security validated** - No privilege escalation vectors
- **Audit logged** - Complete operation logging
- **Tested thoroughly** - Comprehensive test coverage

## Pull Request Process

### Before Submitting
1. **Fork repository** and create feature branch
2. **Implement changes** with comprehensive tests
3. **Update documentation** for all changes
4. **Run full test suite** - All tests must pass
5. **Security validation** - Run security test suite

### PR Requirements
- **Clear description** - What, why, and how
- **Issue reference** - Link to related issues
- **Breaking changes** - Document any breaking changes
- **Testing evidence** - Screenshots or logs showing tests pass
- **Documentation updates** - All docs updated

### Review Process
1. **Automated testing** - CI/CD pipeline validation
2. **Code review** - Maintainer code review
3. **Security review** - Security team approval (if needed)
4. **Documentation review** - Technical writing review
5. **Final approval** - Maintainer approval for merge

## Testing

### Test Categories
- **Unit tests** - Individual component testing
- **Integration tests** - Component interaction testing
- **Security tests** - Permission and security validation
- **End-to-end tests** - Complete user workflow testing

### Running Tests

```bash
# Run unit tests
python -m pytest tests/unit/

# Run integration tests (requires Proxmox)
python -m pytest tests/integration/

# Run security validation
./scripts/security/comprehensive-security-validation.sh

# Run installation test
./scripts/install/test-installation.sh
```

### Test Coverage Requirements
- **New features** - 100% test coverage required
- **Bug fixes** - Include regression test
- **Security changes** - Comprehensive security test coverage
- **Documentation** - Include example validation

## Development Workflow

### Feature Development
1. **Create issue** - Describe feature or bug
2. **Fork and branch** - Create feature branch
3. **Develop incrementally** - Small, focused commits
4. **Test thoroughly** - Unit, integration, security tests
5. **Document completely** - Update all relevant docs
6. **Submit PR** - Follow PR template

### Hotfix Process
1. **Create hotfix branch** from main
2. **Implement minimal fix** - Focus on specific issue
3. **Test extensively** - Extra validation for production
4. **Fast-track review** - Expedited review process
5. **Deploy immediately** - Critical fix deployment

## Code Review Guidelines

### For Authors
- **Self-review first** - Review your own code thoroughly
- **Small PRs** - Keep changes focused and reviewable
- **Clear commits** - Descriptive commit messages
- **Respond promptly** - Address review feedback quickly

### For Reviewers
- **Security focus** - Always consider security implications
- **User impact** - Consider end-user experience
- **Constructive feedback** - Helpful, actionable comments
- **Timely reviews** - Respond within 24-48 hours

## Getting Help

### Development Support
- **Documentation** - Check docs/ for detailed guides
- **Issues** - Search existing issues for similar problems
- **Discussions** - Use GitHub Discussions for questions
- **Security** - Email security@your-domain.com for security issues

### Community Guidelines
- **Be respectful** - Professional and inclusive communication
- **Be helpful** - Share knowledge and assist others
- **Be patient** - Allow time for responses
- **Follow guidelines** - Adhere to project standards

## Recognition

Contributors will be recognized in:
- **CHANGELOG.md** - Feature and fix attribution
- **README.md** - Contributor acknowledgments
- **Release notes** - Major contribution highlights

Thank you for contributing to Proxmox MCP! Your contributions help make enterprise-grade Proxmox management accessible to everyone.