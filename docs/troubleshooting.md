# Troubleshooting Guide

This guide covers common issues and solutions for the Koinos Node Installer.

## Installation Issues

### "Permission denied" errors

**Problem**: Script fails with permission errors
```bash
Permission denied: cannot create directory
```

**Solutions**:
```bash
# Ensure you're not running as root
whoami  # Should NOT return 'root'

# Check if you have sudo privileges
sudo -v

# If the above fails, contact your system administrator
```

### Docker installation fails

**Problem**: Docker installation errors on Ubuntu/Debian
```bash
E: Package 'docker-ce' has no installation candidate
```

**Solutions**:
```bash
# Update package lists
sudo apt-get update

# Check Ubuntu/Debian version compatibility
lsb_release -a

# For older systems, try installing from snap
sudo snap install docker

# Verify installation
docker --version
```

### Insufficient disk space

**Problem**: Installation fails due to disk space
```bash
[ERROR] Insufficient disk space. Need at least 100GB free
```

**Solutions**:
```bash
# Check current disk usage
df -h

# Clean up system
sudo apt-get autoremove
sudo apt-get autoclean
docker system prune -af  # If Docker is installed

# Consider upgrading to larger storage
```

### Firewall configuration fails

**Problem**: UFW commands fail
```bash
ufw: command not found
```

**Solutions**:
```bash
# Install UFW
sudo apt-get install ufw

# Or configure iptables manually
sudo iptables -A INPUT -p tcp --dport 8081 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
```

## Runtime Issues

### Node won't start

**Problem**: Services fail to start after installation
```bash
docker compose ps  # Shows containers as "Exit 1"
```

**Solutions**:
```bash
# Check Docker service
sudo systemctl status docker
sudo systemctl start docker

# Check logs
cd ~/koinos
docker compose logs

# Restart services
docker compose --profile all down
docker compose --profile all up -d

# Check system resources
free -h
df -h
```

### API not responding

**Problem**: API endpoints return connection errors
```bash
curl: (7) Failed to connect to localhost port 8080: Connection refused
```

**Solutions**:
```bash
# Check if containers are running
docker compose ps

# Check specific service logs
docker compose logs jsonrpc
docker compose logs cors-proxy

# Verify ports are listening
sudo netstat -tlnp | grep :8080
sudo netstat -tlnp | grep :8081

# Restart API services
docker compose restart jsonrpc cors-proxy
```

### Slow sync or stuck sync

**Problem**: Node appears to stop syncing
```bash
# Same block height for extended period
~/koinos-status.sh  # Shows no progress
```

**Solutions**:
```bash
# Check if sync is actually stuck
docker compose logs chain | tail -20

# Look for error messages
docker compose logs | grep -i error

# Check peer connections
docker compose logs p2p | tail -10

# Restart chain service
docker compose restart chain

# If persistent, try fresh snapshot
docker compose --profile all down
rm -rf ~/.koinos
# Re-run snapshot download from install script
```

### High memory usage

**Problem**: System running out of memory
```bash
# System becomes unresponsive
free -h  # Shows very low available memory
```

**Solutions**:
```bash
# Check which containers use most memory
docker stats --no-stream

# Add swap space (temporary fix)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Consider upgrading RAM or optimizing services
# Edit ~/koinos/.env to reduce memory usage:
KOINOS_JOBS=2  # Reduce from 4
```

### Docker group permission issues

**Problem**: Docker commands require sudo
```bash
Got permission denied while trying to connect to Docker daemon
```

**Solutions**:
```bash
# Check if user is in docker group
groups | grep docker

# Add user to docker group (if not already)
sudo usermod -aG docker $USER

# Apply group changes
newgrp docker

# If still failing, logout and login again
```

## Network Issues

### Can't access API from external hosts

**Problem**: API works locally but not from other machines
```bash
# This works:
curl http://localhost:8081
# This doesn't:
curl http://YOUR_SERVER_IP:8081
```

**Solutions**:
```bash
# Check if ports are bound to all interfaces
sudo netstat -tlnp | grep :8081
# Should show 0.0.0.0:8081, not 127.0.0.1:8081

# Check firewall
sudo ufw status
# Should show 8081/tcp ALLOW

# Test from server itself
curl http://$(curl -s ifconfig.me):8081

# Check cloud provider security groups/firewall rules
```

### CORS errors in web applications

**Problem**: Browser blocks API requests
```javascript
Access to fetch at 'http://your-server:8081' from origin 'https://myapp.com' 
has been blocked by CORS policy
```

**Solutions**:
```bash
# Verify CORS proxy is running
docker compose ps | grep cors-proxy

# Check CORS proxy logs
docker compose logs cors-proxy

# Test CORS headers
curl -H "Origin: https://example.com" \
     -H "Access-Control-Request-Method: POST" \
     -H "Access-Control-Request-Headers: Content-Type" \
     -X OPTIONS \
     http://your-server:8081

# Should return CORS headers in response
```

## Data Issues

### Blockchain data corruption

**Problem**: Node reports database errors
```bash
Error opening database: corruption detected
```

**Solutions**:
```bash
# Stop the node
docker compose --profile all down

# Backup current data
mv ~/.koinos ~/.koinos_corrupt_backup

# Download fresh snapshot
cd ~
LATEST=$(curl -s https://backup.koinosblocks.com/ | grep -oP 'backup_\d{4}-\d{2}-\d{2}\.tar\.gz' | sort | tail -n 1)
wget https://backup.koinosblocks.com/$LATEST
tar -xzf $LATEST
mv backup ~/.koinos

# Restart node
cd ~/koinos && docker compose --profile all up -d
```

### Snapshot extraction fails

**Problem**: Snapshot download or extraction errors
```bash
tar: Error is not recoverable: exiting now
```

**Solutions**:
```bash
# Check download integrity
ls -la backup_*.tar.gz
# File should be several GB in size

# Try different extraction method
gunzip backup_*.tar.gz
tar -xf backup_*.tar

# Or download again
rm backup_*.tar.gz
# Re-run download commands
```

## Performance Issues

### High CPU usage

**Problem**: System shows constantly high CPU usage
```bash
top  # Shows Docker processes using high CPU
```

**Solutions**:
```bash
# Check which service is using CPU
docker stats

# Reduce parallel jobs in Koinos
nano ~/koinos/.env
# Change: KOINOS_JOBS=2  # From default 4

# Restart services
docker compose --profile all restart

# Consider upgrading to more CPU cores
```

### Disk I/O bottlenecks

**Problem**: Slow performance with high disk wait times
```bash
iostat -x 1  # Shows high %util on storage device
```

**Solutions**:
```bash
# Check disk usage patterns
iotop  # Install with: sudo apt-get install iotop

# Optimize Docker storage driver
sudo nano /etc/docker/daemon.json
# Add: {"storage-driver": "overlay2"}

# Restart Docker
sudo systemctl restart docker

# Consider upgrading to NVMe SSD
```

## Getting Help

If these solutions don't resolve your issue:

1. **Check logs thoroughly**:
   ```bash
   # System logs
   sudo journalctl -u docker
   
   # Application logs  
   cd ~/koinos
   docker compose logs > debug.log
   ```

2. **Gather system information**:
   ```bash
   # Create diagnostic info
   echo "=== System Info ===" > debug-info.txt
   lsb_release -a >> debug-info.txt
   free -h >> debug-info.txt
   df -h >> debug-info.txt
   docker --version >> debug-info.txt
   docker compose ps >> debug-info.txt
   ```

3. **Open GitHub Issue** with:
   - Your system information
   - Complete error messages
   - Steps you've already tried
   - Log files (if relevant)

4. **Community Support**:
   - GitHub Discussions for general help
   - Koinos Discord for real-time support