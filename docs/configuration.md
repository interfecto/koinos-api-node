# Configuration Guide

This guide covers advanced configuration options for your Koinos node.

## Environment Variables

The main configuration is stored in `~/koinos/.env`. You can modify these settings after installation.

### Network Interfaces

```bash
# Make APIs publicly accessible (default after install)
JSONRPC_INTERFACE=0.0.0.0
GRPC_INTERFACE=0.0.0.0
REST_INTERFACE=0.0.0.0

# For localhost-only access, use:
# JSONRPC_INTERFACE=127.0.0.1
# GRPC_INTERFACE=127.0.0.1
# REST_INTERFACE=127.0.0.1
```

### Port Configuration

```bash
# Default ports (change if needed)
JSONRPC_PORT=8080
GRPC_PORT=50051
REST_PORT=3000
P2P_PORT=8888
AMQP_PORT=5672
AMQP_ADMIN_PORT=15672
```

### Performance Settings

```bash
# Number of worker threads (default: number of CPU cores)
KOINOS_JOBS=4

# Logging level (debug, info, warn, error)
KOINOS_LOG_LEVEL=warn

# Log format (true for JSON, false for text)
KOINOS_LOG_JSON=false

# Database settings
CHAIN_STATE_DB_MAX_OPEN_FILES=1000
ACCOUNT_HISTORY_DB_MAX_OPEN_FILES=1000
```

### Service Profiles

Control which services run:

```bash
# Run all services (default)
COMPOSE_PROFILES=all

# Or specify specific services:
# COMPOSE_PROFILES=jsonrpc,grpc,rest

# Available profiles:
# - jsonrpc: JSON-RPC API
# - grpc: gRPC API  
# - rest: REST API
# - block_producer: Block production (advanced)
# - transaction_store: Transaction indexing
# - contract_meta_store: Contract metadata
# - account_history: Account history indexing
```

## Docker Compose Customization

### Resource Limits

Edit `~/koinos/docker-compose.yml` to adjust resource limits:

```yaml
services:
  chain:
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2'
        reservations:
          memory: 2G
          cpus: '1'
```

### Volume Configuration

```yaml
services:
  chain:
    volumes:
      - "${BASEDIR}:/koinos"
      # Add additional volumes if needed
      - "/path/to/custom/config:/koinos/custom"
```

## CORS Proxy Configuration

### Nginx Settings

Edit `~/koinos/nginx.conf` to customize CORS behavior:

```nginx
# Allow specific origins instead of all
add_header 'Access-Control-Allow-Origin' 'https://yourdapp.com' always;

# Adjust rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=50r/s;  # 50 requests/second
limit_req zone=api burst=100 nodelay;  # Burst to 100 requests

# Add custom headers
add_header 'X-Koinos-Node' 'community-installer' always;
```

### Custom CORS Configuration

For production applications, consider restricting origins:

```nginx
# Replace the blanket CORS headers with specific ones
map $http_origin $cors_origin {
    default "";
    "https://yourdapp.com" "https://yourdapp.com";
    "https://staging.yourdapp.com" "https://staging.yourdapp.com";
}

server {
    # ... existing config ...
    
    location / {
        # ... existing proxy config ...
        
        add_header 'Access-Control-Allow-Origin' $cors_origin always;
        # ... rest of headers ...
    }
}
```

## Security Configuration

### Firewall Customization

```bash
# Remove public access to certain APIs
sudo ufw delete allow 8080/tcp  # Remove direct JSON-RPC access
sudo ufw delete allow 50051/tcp  # Remove gRPC access

# Allow specific IP ranges only
sudo ufw allow from 10.0.0.0/8 to any port 8080
sudo ufw allow from 192.168.0.0/16 to any port 8080
```

### API Key Authentication

Add API key authentication to nginx:

```nginx
# Add to nginx.conf
map $http_x_api_key $api_key_valid {
    default 0;
    "your-secret-api-key-here" 1;
}

server {
    location / {
        # Check API key for non-OPTIONS requests
        if ($request_method != OPTIONS) {
            set $auth_required 1;
        }
        if ($api_key_valid = 1) {
            set $auth_required 0;
        }
        if ($auth_required = 1) {
            return 401 "Unauthorized\n";
        }
        
        # ... rest of proxy config ...
    }
}
```

## Performance Tuning

### High-Traffic Optimization

For nodes serving many requests:

```bash
# Increase connection limits in nginx.conf
events {
    worker_connections 2048;  # Increase from 1024
    use epoll;
    multi_accept on;
}

http {
    # Connection pooling
    upstream jsonrpc_backend {
        server jsonrpc:8080 max_fails=3 fail_timeout=30s;
        keepalive 64;  # Increase from 32
    }
    
    # Caching (for repeated queries)
    proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=api_cache:10m inactive=60m;
    
    server {
        location / {
            # Enable caching for GET requests
            proxy_cache api_cache;
            proxy_cache_valid 200 1m;  # Cache successful responses for 1 minute
            proxy_cache_key "$request_method$request_uri$request_body";
            
            # ... existing config ...
        }
    }
}
```

### Database Optimization

```bash
# In ~/koinos/.env, add:

# Increase database cache sizes
CHAIN_STATE_DB_CACHE_SIZE=512MB
ACCOUNT_HISTORY_DB_CACHE_SIZE=256MB

# Adjust write buffer sizes
CHAIN_STATE_DB_WRITE_BUFFER_SIZE=64MB
ACCOUNT_HISTORY_DB_WRITE_BUFFER_SIZE=32MB
```

### SSD Optimization

```bash
# Add to /etc/sysctl.conf for SSD optimization
vm.swappiness=1
vm.vfs_cache_pressure=50
vm.dirty_background_ratio=5
vm.dirty_ratio=10

# Apply settings
sudo sysctl -p
```

## Monitoring Configuration

### Built-in Metrics

Enable Prometheus metrics (if available):

```bash
# Add to ~/koinos/.env
KOINOS_PROMETHEUS_ENABLED=true
KOINOS_PROMETHEUS_PORT=9090
```

### Log Rotation

Configure log rotation to prevent disk fill:

```bash
# Create logrotate config
sudo nano /etc/logrotate.d/koinos
```

```
/var/lib/docker/containers/*/*-json.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        docker kill -s USR1 $(docker ps -q) 2>/dev/null || true
    endscript
}
```

## Network Configuration

### Custom P2P Settings

```bash
# In ~/koinos/.env
P2P_INTERFACE=0.0.0.0  # Listen on all interfaces
P2P_PORT=8888          # Default P2P port

# Advanced P2P settings (if supported)
P2P_MAX_PEERS=50
P2P_SEED_NODES=seed1.koinos.io,seed2.koinos.io
```

### Load Balancer Setup

For multiple nodes behind a load balancer:

```nginx
# On load balancer
upstream koinos_cluster {
    server node1.example.com:8081;
    server node2.example.com:8081;
    server node3.example.com:8081;
    
    # Health checking
    health_check interval=30s;
}

server {
    listen 80;
    location / {
        proxy_pass http://koinos_cluster;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## SSL/TLS Configuration

### Let's Encrypt with Certbot

```bash
# Install certbot
sudo apt-get install certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

### Manual SSL Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /path/to/certificate.crt;
    ssl_certificate_key /path/to/private.key;
    
    # SSL optimization
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    
    location / {
        proxy_pass http://jsonrpc_backend;
        # ... existing proxy config ...
    }
}
```

## Applying Configuration Changes

After modifying configuration files:

```bash
# Restart specific services
docker compose restart nginx cors-proxy

# Or restart all services
docker compose --profile all restart

# For .env changes, recreate containers
docker compose --profile all down
docker compose --profile all up -d

# Check that changes took effect
docker compose ps
~/koinos-status.sh
```

## Configuration Validation

Test your configuration changes:

```bash
# Test nginx configuration syntax
docker compose exec cors-proxy nginx -t

# Test API endpoints
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"chain.get_head_info","params":{},"id":1}' \
  http://localhost:8081

# Monitor logs for errors
docker compose logs --tail=50
```