#!/bin/bash

# Koinos API Node Installer
# Usage: curl -sSL https://your-domain.com/install-koinos.sh | bash
# Or: wget -qO- https://your-domain.com/install-koinos.sh | bash

set -e  # Exit on any error

echo "=================================="
echo "🚀 Koinos API Node Installer"
echo "=================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check operating system
if ! grep -q "Ubuntu\|Debian" /etc/os-release; then
    print_error "This installer supports Ubuntu and Debian only."
    exit 1
fi

print_status "Checking system requirements..."

# Check available disk space (need at least 100GB free)
AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
if [ $AVAILABLE_SPACE -lt 100 ]; then
    print_error "Insufficient disk space. Need at least 100GB free, found ${AVAILABLE_SPACE}GB"
    exit 1
fi

# Check RAM (need at least 6GB)
TOTAL_RAM=$(free -g | awk 'NR==2{print $2}')
if [ $TOTAL_RAM -lt 6 ]; then
    print_warning "System has ${TOTAL_RAM}GB RAM. Recommended: 8GB or more."
fi

print_success "System requirements check passed"

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    # Remove old Docker versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update package index
    sudo apt-get update
    
    # Install dependencies
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's GPG key
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    print_success "Docker installed successfully"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Check if ufw is available
    if command -v ufw >/dev/null 2>&1; then
        # Enable firewall
        sudo ufw --force enable
        
        # Allow SSH (important!)
        sudo ufw allow ssh
        
        # Allow Koinos ports
        sudo ufw allow 8081/tcp comment 'Koinos CORS API'
        sudo ufw allow 8080/tcp comment 'Koinos JSON-RPC'
        sudo ufw allow 8888/tcp comment 'Koinos P2P'
        sudo ufw allow 50051/tcp comment 'Koinos gRPC'
        sudo ufw allow 3000/tcp comment 'Koinos REST'
        
        print_success "Firewall configured"
    else
        print_warning "UFW firewall not available. Please configure firewall manually."
    fi
}

# Function to setup Koinos
setup_koinos() {
    print_status "Setting up Koinos node..."
    
    # Clone repository
    cd $HOME
    if [ -d "koinos" ]; then
        print_warning "Koinos directory already exists. Backing it up..."
        mv koinos koinos_backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    git clone https://github.com/koinos/koinos
    cd koinos
    
    # Copy configuration files
    cp -r config-example config
    cp env.example .env
    
    # Configure .env file
    print_status "Configuring environment variables..."
    
    # Update interfaces to be publicly accessible
    sed -i 's/JSONRPC_INTERFACE=127.0.0.1/JSONRPC_INTERFACE=0.0.0.0/' .env
    sed -i 's/GRPC_INTERFACE=127.0.0.1/GRPC_INTERFACE=0.0.0.0/' .env
    sed -i 's/REST_INTERFACE=127.0.0.1/REST_INTERFACE=0.0.0.0/' .env
    
    # Add performance optimizations
    cat >> .env << EOF

# Performance optimizations
KOINOS_LOG_LEVEL=warn
KOINOS_JOBS=$(nproc)
KOINOS_LOG_JSON=false
EOF
    
    print_success "Koinos configuration completed"
}

# Function to setup CORS proxy
setup_cors_proxy() {
    print_status "Setting up CORS proxy..."
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
EOF
    
    # Create nginx.conf
    cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
    use epoll;
}

http {
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=20r/s;
    
    # Connection pooling
    upstream jsonrpc_backend {
        server jsonrpc:8080 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }
    
    server {
        listen 8081;
        
        # Increase timeouts
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Enable compression
        gzip on;
        gzip_types application/json text/plain;
        
        # Rate limiting
        limit_req zone=api burst=50 nodelay;
        
        location / {
            proxy_pass http://jsonrpc_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Connection "";
            proxy_http_version 1.1;
            
            # CORS headers
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE' always;
            add_header 'Access-Control-Allow-Headers' '*' always;
            
            if ($request_method = OPTIONS ) {
                add_header 'Access-Control-Allow-Origin' '*';
                add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE';
                add_header 'Access-Control-Allow-Headers' '*';
                add_header 'Content-Length' 0;
                add_header 'Content-Type' 'text/plain charset=UTF-8';
                return 204;
            }
        }
        
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    # Update docker-compose.yml to include CORS proxy
    cat >> docker-compose.yml << 'EOF'

   cors-proxy:
      build: .
      restart: always
      profiles: ["jsonrpc", "api", "all"]
      depends_on:
         - jsonrpc
      ports:
         - "8081:8081"
      deploy:
         resources:
            limits:
               memory: 512M
               cpus: '0.5'
            reservations:
               memory: 256M
               cpus: '0.25'
EOF
    
    print_success "CORS proxy configured"
}

# Function to download blockchain snapshot
download_snapshot() {
    print_status "Downloading blockchain snapshot (this may take a while)..."
    
    cd $HOME
    
    # Get latest snapshot
    LATEST=$(curl -s https://backup.koinosblocks.com/ | grep -oP 'backup_\d{4}-\d{2}-\d{2}\.tar\.gz' | sort | tail -n 1)
    
    if [ -z "$LATEST" ]; then
        print_error "Could not find latest snapshot"
        exit 1
    fi
    
    print_status "Downloading: $LATEST"
    wget --progress=bar:force https://backup.koinosblocks.com/$LATEST -O $LATEST
    
    print_status "Extracting snapshot..."
    tar -xzf $LATEST
    
    # Move to correct location
    if [ -d "backup" ]; then
        mv backup ~/.koinos
    elif [ -d "${LATEST%.*.*}" ]; then
        mv "${LATEST%.*.*}" ~/.koinos
    else
        print_error "Could not find extracted snapshot directory"
        ls -la
        exit 1
    fi
    
    # Clean up
    rm $LATEST
    
    print_success "Blockchain snapshot installed"
}

# Function to create management scripts
create_management_scripts() {
    print_status "Creating management scripts..."
    
    # Node status script
    cat > $HOME/koinos-status.sh << 'EOF'
#!/bin/bash
echo "=== Koinos Node Status $(date) ==="
echo
echo "=== Container Status ==="
cd ~/koinos && docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
echo
echo "=== Current Block Height ==="
CURRENT_HEIGHT=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"chain.get_head_info","params":{},"id":1}' \
  http://localhost:8080 | jq -r '.result.head_topology.height' 2>/dev/null)

if [ "$CURRENT_HEIGHT" != "null" ] && [ -n "$CURRENT_HEIGHT" ]; then
    echo "Height: $CURRENT_HEIGHT"
else
    echo "API not ready or still syncing"
fi
echo
echo "=== System Resources ==="
echo "Memory: $(free -h | awk 'NR==2{printf "%s/%s (%.1f%%)\n", $3,$2,$3*100/$2}')"
echo "Disk: $(df -h / | awk 'NR==2{printf "%s/%s (%s)\n", $3,$2,$5}')"
echo
echo "=== Recent Logs ==="
cd ~/koinos && docker compose logs --tail=3 chain
EOF
    chmod +x $HOME/koinos-status.sh
    
    # Node management script
    cat > $HOME/koinos-manage.sh << 'EOF'
#!/bin/bash
case "$1" in
    start)
        echo "Starting Koinos node..."
        cd ~/koinos && docker compose --profile all up -d
        ;;
    stop)
        echo "Stopping Koinos node..."
        cd ~/koinos && docker compose --profile all down
        ;;
    restart)
        echo "Restarting Koinos node..."
        cd ~/koinos && docker compose --profile all restart
        ;;
    logs)
        echo "Showing logs (Ctrl+C to exit)..."
        cd ~/koinos && docker compose logs -f chain
        ;;
    update)
        echo "Updating Koinos node..."
        cd ~/koinos && docker compose --profile all down
        docker compose pull
        docker compose --profile all up -d
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|update}"
        echo "  start   - Start the Koinos node"
        echo "  stop    - Stop the Koinos node"
        echo "  restart - Restart the Koinos node"
        echo "  logs    - Show node logs"
        echo "  update  - Update and restart node"
        ;;
esac
EOF
    chmod +x $HOME/koinos-manage.sh
    
    print_success "Management scripts created"
}

# Function to start the node
start_node() {
    print_status "Starting Koinos node..."
    
    cd $HOME/koinos
    
    # Start with new group membership (Docker group)
    sg docker -c "docker compose --profile all up -d"
    
    print_success "Koinos node started"
}

# Function to test APIs
test_apis() {
    print_status "Waiting for APIs to be ready..."
    
    # Wait for services to start
    sleep 30
    
    # Test JSON-RPC API
    if curl -s -X POST -H "Content-Type: application/json" \
       -d '{"jsonrpc":"2.0","method":"chain.get_head_info","params":{},"id":1}' \
       http://localhost:8080 > /dev/null; then
        print_success "JSON-RPC API is responding"
    else
        print_warning "JSON-RPC API not ready yet (this is normal during initial startup)"
    fi
    
    # Test CORS proxy
    if curl -s -X POST -H "Content-Type: application/json" \
       -d '{"jsonrpc":"2.0","method":"chain.get_head_info","params":{},"id":1}' \
       http://localhost:8081 > /dev/null; then
        print_success "CORS proxy is responding"
    else
        print_warning "CORS proxy not ready yet (this is normal during initial startup)"
    fi
}

# Main installation flow
main() {
    print_status "Starting Koinos node installation..."
    
    # Check if Docker is already installed
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    else
        print_success "Docker already installed"
    fi
    
    configure_firewall
    setup_koinos
    setup_cors_proxy
    download_snapshot
    create_management_scripts
    start_node
    test_apis
    
    echo
    echo "=================================="
    echo "🎉 Installation Complete!"
    echo "=================================="
    echo
    echo "Your Koinos API node is now running!"
    echo
    echo "API Endpoints:"
    echo "• CORS Proxy (recommended): http://$(curl -s ifconfig.me):8081"
    echo "• JSON-RPC Direct: http://$(curl -s ifconfig.me):8080"
    echo "• gRPC: http://$(curl -s ifconfig.me):50051"
    echo "• REST API: http://$(curl -s ifconfig.me):3000"
    echo
    echo "Management Commands:"
    echo "• Check status: ~/koinos-status.sh"
    echo "• Manage node: ~/koinos-manage.sh [start|stop|restart|logs|update]"
    echo "• View logs: docker compose -f ~/koinos/docker-compose.yml logs -f chain"
    echo
    echo "The node is currently syncing. This may take 1-3 days depending on"
    echo "the snapshot age. Monitor progress with: ~/koinos-status.sh"
    echo
    print_warning "IMPORTANT: You may need to log out and back in for Docker group changes to take effect."
}

# Run main function
main "$@"