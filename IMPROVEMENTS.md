# Installation Script Improvements & Optimizations

## Summary of Changes
This document outlines all improvements and optimizations made to the `install.sh` script for better reliability, compatibility, and user experience.

## Key Improvements

### 1. Enhanced Error Handling
- **Added `set -euo pipefail`**: Script now exits on undefined variables and pipe failures, not just command errors
- **Cleanup trap**: Added interrupt handler that cleans up background processes and temporary files on script termination
- **Timeout protection**: Added timeouts to network operations to prevent hanging
- **Better error messages**: More descriptive error outputs with actionable solutions

### 2. Cross-Platform Compatibility
- **macOS/BSD support**: Fixed grep commands to use POSIX-compliant sed instead of GNU grep's `-P` flag
- **CPU core detection**: Added multiple fallbacks (`nproc`, `sysctl`, `getconf`) for different systems
- **Disk space calculation**: Handle both Linux (`df -BG`) and macOS/BSD df output formats
- **sg command fallback**: Added fallback for systems without `sg` command (macOS, some Linux distros)

### 3. OS Detection Improvements
- **Flexible OS checking**: Now supports Ubuntu/Debian derivatives by checking `ID_LIKE` field
- **Interactive prompts**: Asks user to confirm installation on unsupported systems instead of failing
- **Better distro detection**: Improved Docker repository selection based on OS distribution

### 4. Network & Download Optimizations
- **External IP detection**: Added multiple fallback services (ifconfig.me, icanhazip.com)
- **Connection limits**: Optimized aria2c connections based on server capabilities
- **Exponential backoff**: Progressive wait times between download retries
- **Speed monitoring**: Better download speed detection with fallback patterns

### 5. Docker & Container Improvements
- **Restart policies**: Added `unless-stopped` to ensure services restart after reboot
- **Log rotation**: Configured log size limits to prevent disk filling
- **CORS proxy resilience**: Added fallback upstream servers for better connectivity
- **Docker Compose compatibility**: Better handling of Docker Compose v1 vs v2

### 6. Resource Management
- **Default variables**: Set defaults for HOME, USER, and other critical variables
- **Memory optimization**: Added container-specific log rotation settings
- **Disk space awareness**: Better calculation of required space with clear user feedback

## Technical Details

### Error Handling Changes
```bash
# Before:
set -e

# After:
set -euo pipefail  # More comprehensive error detection
```

### Cross-Platform grep Fix
```bash
# Before (GNU-specific):
grep -oP 'backup_\d{4}-\d{2}-\d{2}\.tar\.gz'

# After (POSIX-compliant):
sed -n 's/.*\(backup_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\.tar\.gz\).*/\1/p'
```

### CPU Core Detection
```bash
# Before:
CPU_CORES=$(nproc)

# After (with fallbacks):
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
```

### Disk Space Calculation
```bash
# After (handles both Linux and macOS):
if df -BG . >/dev/null 2>&1; then
    # Linux format with -BG flag
    AVAILABLE_SPACE=$(df -BG . | awk 'NR==2 {print int($4)}')
else
    # macOS/BSD format - convert KB to GB
    AVAILABLE_KB=$(df . | awk 'NR==2 {print $4}')
    AVAILABLE_SPACE=$((AVAILABLE_KB / 1024 / 1024))
fi
```

### Docker Group Handling
```bash
# After (with fallback):
if command -v sg >/dev/null 2>&1; then
    sg docker -c "docker compose --profile all up -d"
else
    # Fallback for systems without sg command
    docker compose --profile all up -d || {
        print_warning "May need to logout/login for Docker group changes"
        docker compose --profile all up -d
    }
fi
```

### CORS Proxy Upstream Configuration
```nginx
# After (with fallback servers):
upstream koinos_jsonrpc {
    server host.docker.internal:8080 max_fails=2 fail_timeout=10s;
    server 172.17.0.1:8080 backup max_fails=2 fail_timeout=10s;
}
```

## Benefits

1. **Improved Reliability**: Script handles more edge cases and failure scenarios gracefully
2. **Better Compatibility**: Works on more systems including macOS for development
3. **Clearer Feedback**: Users get better information about what's happening and why
4. **Faster Recovery**: Exponential backoff and better retry logic reduces failed installations
5. **Resource Efficiency**: Log rotation and optimized settings prevent resource exhaustion
6. **Production Ready**: Restart policies ensure services stay running after reboots

## Testing Recommendations

1. **Test on Fresh Ubuntu 22.04**: Primary target platform
2. **Test on Debian 11/12**: Secondary supported platform
3. **Test interruption handling**: Ctrl+C during download and extraction
4. **Test disk space scenarios**: Low disk space warnings
5. **Test network failures**: Slow connections, disconnections
6. **Test Docker variations**: Docker Desktop, Docker CE, rootless Docker

## Future Enhancements

1. **Progress bars**: Add better visual progress indicators
2. **Configuration file**: Allow customization via config file
3. **Backup/restore**: Built-in blockchain data backup functionality
4. **Health checks**: More comprehensive service health monitoring
5. **Auto-updates**: Optional automatic node updates
6. **Multi-node support**: Deploy multiple nodes from single script

## Conclusion

These improvements make the installation script more robust, user-friendly, and compatible with a wider range of systems while maintaining the core functionality of deploying a Koinos node efficiently.