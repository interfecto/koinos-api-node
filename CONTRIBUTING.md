# Contributing to Koinos Node Installer

Thank you for your interest in contributing to the Koinos Node Installer! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Issues

- Use GitHub Issues to report bugs or request features
- Search existing issues before creating new ones
- Provide clear, detailed descriptions
- Include system information (OS version, hardware specs)
- Add logs or error messages when reporting bugs

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly on a clean system
5. Commit with clear messages (`git commit -m 'Add amazing feature'`)
6. Push to your branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Development Guidelines

### Testing Requirements

Before submitting a PR, test your changes on:
- Fresh Ubuntu 20.04 LTS
- Fresh Ubuntu 22.04 LTS  
- Fresh Ubuntu 24.04 LTS
- At least one Debian version

### Code Style

**Shell Scripts:**
- Use `#!/bin/bash` shebang
- Follow Google Shell Style Guide
- Use `set -e` for error handling
- Include meaningful comments
- Use consistent indentation (2 spaces)

**Example:**
```bash
#!/bin/bash
set -e

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Continue with installation...
}
```

### Documentation

- Update README.md for user-facing changes
- Document new configuration options
- Include examples for new features
- Update troubleshooting guide for known issues

## Project Structure

```
koinos-node-installer/
├── install.sh              # Main installer script
├── README.md               # Project documentation
├── CONTRIBUTING.md         # This file
├── LICENSE                 # MIT License
├── CHANGELOG.md           # Version history
├── docs/                  # Detailed documentation
│   ├── troubleshooting.md
│   ├── configuration.md
│   ├── api-usage.md
│   └── backup-setup.md
├── scripts/               # Helper scripts
│   ├── koinos-status.sh
│   ├── koinos-manage.sh
│   └── backup-setup.sh
└── tests/                 # Test scripts (future)
    └── test-install.sh
```

## Areas for Contribution

### High Priority

- **Testing**: Test on different OS versions and cloud providers
- **Documentation**: Improve troubleshooting guides and examples
- **Error Handling**: Better error messages and recovery options
- **Performance**: Optimization for different hardware configurations

### Medium Priority

- **Monitoring**: Built-in monitoring and alerting features
- **SSL/TLS**: HTTPS support with Let's Encrypt
- **Backup**: Automated backup and restore functionality
- **Updates**: Automatic update mechanisms

### Future Enhancements

- **Multi-arch**: Support for ARM64 systems
- **Testnet**: Support for Koinos testnet
- **Docker Images**: Pre-built Docker images
- **Kubernetes**: Helm charts for Kubernetes deployment

## Contribution Examples

### Adding OS Support

To add support for a new OS distribution:

1. Update OS detection in `install.sh`
2. Add distribution-specific package commands
3. Test on the new OS
4. Update documentation

### Improving Error Handling

Good error handling includes:
- Clear error messages
- Suggestions for fixing issues
- Graceful cleanup on failure
- Logging for debugging

### Adding Configuration Options

When adding new configuration options:
- Use environment variables for runtime config
- Provide sensible defaults
- Document in `docs/configuration.md`
- Include examples

## Testing Checklist

Before submitting changes:

- [ ] Test on clean Ubuntu system
- [ ] Test with limited resources (4GB RAM)
- [ ] Verify all APIs respond after installation
- [ ] Check firewall configuration
- [ ] Test management scripts
- [ ] Verify cleanup on installation failure
- [ ] Update relevant documentation

## Code Review Process

1. Maintainers review all pull requests
2. At least one approval required before merge
3. All tests must pass
4. Documentation must be updated
5. Breaking changes require discussion

## Getting Help

- Open a GitHub Issue for bugs or feature requests
- Use GitHub Discussions for general questions
- Join the Koinos community Discord for real-time help
- Tag maintainers in PRs that need attention

## Recognition

Contributors will be:
- Listed in project contributors
- Mentioned in changelog for significant contributions  
- Invited to join the maintainer team for sustained contributions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.