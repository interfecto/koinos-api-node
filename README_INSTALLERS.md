# Koinos Node Installers - Comparison Guide

This repository provides two installation scripts for deploying a Koinos node. Choose the one that best fits your needs.

## Quick Decision Guide

- **Use `install.sh`** if you want a quick, simple installation for development or testing
- **Use `installHardened.sh`** if you're deploying to production or want enhanced security

## Installation Scripts

### 1. `install.sh` - Standard Installer

The standard installer provides a quick and straightforward way to get a Koinos node running.

**Features:**
- ✅ Quick installation with minimal configuration
- ✅ All APIs exposed on public interfaces (0.0.0.0)
- ✅ Automatic snapshot download with resume support
- ✅ Multi-connection downloads for speed
- ✅ Basic firewall configuration
- ✅ Docker and Docker Compose installation
- ✅ Management scripts included

**Best for:**
- Development environments
- Testing and experimentation
- Local networks
- Quick deployments where security is not critical

**Usage:**
```bash
curl -sSL https://raw.githubusercontent.com/your-repo/install.sh | bash
```

### 2. `installHardened.sh` - Security-Hardened Installer

The hardened installer implements security best practices and production-ready configurations.

**Features:**
- 🔒 **Enhanced Security:**
  - APIs bound to localhost only (not publicly exposed)
  - Public access only through CORS proxy on port 8081
  - Proper firewall configuration with minimal exposure
  - Rate limiting on public endpoints
  - Security headers in nginx configuration

- 💪 **System Requirements Checking:**
  - Enforces minimum 8GB RAM (exits if less)
  - Warns if RAM < 16GB (recommended)
  - Adjusts disk requirements based on node type (100-150GB)
  - Validates all dependencies before starting

- 🎯 **Configuration Options:**
  ```bash
  # Minimal API node (default)
  ./installHardened.sh
  
  # Skip snapshot download
  ./installHardened.sh --no-snapshot
  
  # Full indexer node
  ./installHardened.sh --profile indexer
  
  # Enable P2P port for seeding
  ./installHardened.sh --enable-p2p
  
  # See all options
  ./installHardened.sh --help
  ```

- 📦 **Clean Architecture:**
  - Uses docker-compose.override.yml (doesn't modify upstream files)
  - Separate Dockerfile.cors and nginx.conf files
  - Maintains clean separation from upstream Koinos repository
  - Easy updates without merge conflicts

- 🔧 **Production Features:**
  - Container restart policies (unless-stopped)
  - Log rotation configured
  - Health checks on services
  - Proper error handling with line numbers
  - Validation of docker-compose configuration

**Best for:**
- Production deployments
- Public cloud servers
- Security-conscious deployments
- Professional node operators
- Long-running nodes

**Usage:**
```bash
# Basic installation
curl -sSL https://raw.githubusercontent.com/your-repo/installHardened.sh | bash

# With options
wget https://raw.githubusercontent.com/your-repo/installHardened.sh
chmod +x installHardened.sh
./installHardened.sh --profile indexer --enable-p2p
```

## Key Differences

| Feature | `install.sh` | `installHardened.sh` |
|---------|-------------|---------------------|
| **API Exposure** | All ports public (0.0.0.0) | Localhost only + CORS proxy |
| **Security Level** | Basic | Production-grade |
| **RAM Check** | None | Enforces 8GB minimum |
| **Firewall** | Opens all API ports | Only CORS proxy (8081) |
| **Configuration** | Fixed | Flexible profiles |
| **Docker Compose** | Modifies original | Uses override file |
| **Error Handling** | Basic | Enhanced with line numbers |
| **Dependencies** | Assumes present | Installs missing |
| **Snapshot** | Always downloads | Optional (--no-snapshot) |
| **P2P Port** | Always open | Optional (--enable-p2p) |
| **Log Rotation** | No | Yes |
| **Health Checks** | No | Yes |
| **Rate Limiting** | No | Yes |

## Security Comparison

### `install.sh` - Standard Security
```
Internet → All Ports Open
         ├── 8080 (JSON-RPC) ← Direct Access
         ├── 8081 (CORS Proxy) ← Direct Access
         ├── 50051 (gRPC) ← Direct Access
         ├── 3000 (REST) ← Direct Access
         └── 8888 (P2P) ← Direct Access
```

### `installHardened.sh` - Enhanced Security
```
Internet → Limited Access
         ├── 8081 (CORS Proxy) ← Public Access (Rate Limited)
         └── 8888 (P2P) ← Optional (--enable-p2p)
         
Localhost Only (Secure):
         ├── 8080 (JSON-RPC)
         ├── 50051 (gRPC)
         └── 3000 (REST)
```

## Choosing the Right Installer

### Use `install.sh` when:
- Setting up a development environment
- Testing Koinos features
- Running on a private/secure network
- Need quick setup without configuration
- Learning about Koinos

### Use `installHardened.sh` when:
- Deploying to production
- Running on public cloud (AWS, Google Cloud, etc.)
- Security is a priority
- Need flexibility in configuration
- Running a public API service
- Operating a professional node
- Want better resource management

## Post-Installation

Both installers create management scripts:

```bash
# Check node status
~/koinos-status.sh

# Manage the node
~/koinos-manage.sh start|stop|restart|logs|update|status

# View logs
~/koinos-manage.sh logs chain
~/koinos-manage.sh logs cors-proxy
```

## System Requirements

### Minimum (both installers):
- Ubuntu 20.04+ or Debian 11+
- 4 CPU cores
- 100GB free disk space
- Internet connection

### Recommended (enforced by hardened):
- Ubuntu 22.04 LTS
- 8+ CPU cores  
- 16GB+ RAM (8GB minimum for hardened)
- 150GB+ free disk space for indexer
- Dedicated server or VPS

## Migration

### From `install.sh` to `installHardened.sh`:

1. Stop existing node:
   ```bash
   ~/koinos-manage.sh stop
   ```

2. Backup configuration:
   ```bash
   cp ~/koinos/.env ~/koinos/.env.backup
   ```

3. Run hardened installer:
   ```bash
   ./installHardened.sh --no-snapshot
   ```

The hardened installer will detect existing blockchain data and reuse it.

## Troubleshooting

### Common Issues:

1. **"Insufficient RAM" error (hardened only)**
   - Upgrade to at least 8GB RAM
   - Or use standard installer (not recommended for production)

2. **Firewall blocks SSH**
   - The hardened installer configures firewall safely
   - Standard installer may need manual SSH rule

3. **CORS errors in browser**
   - Hardened: Use port 8081 (CORS proxy)
   - Standard: Can use 8080 or 8081

4. **Can't access APIs remotely**
   - Hardened: This is by design - use CORS proxy on 8081
   - Standard: Check firewall allows ports

## Support

- GitHub Issues: [Report problems](https://github.com/your-repo/issues)
- Documentation: [Koinos Docs](https://docs.koinos.io)
- Community: [Koinos Discord](https://discord.gg/koinos)

## License

Both installers are provided under the MIT License. Use at your own risk.