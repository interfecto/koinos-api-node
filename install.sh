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
    
    # Check available disk space before download (need ~60GB for download + extraction)
    AVAILABLE_SPACE=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    if [ $AVAILABLE_SPACE -lt 60 ]; then
        print_error "Insufficient disk space for snapshot. Need at least 60GB free, found ${AVAILABLE_SPACE}GB"
        print_status "Tip: The snapshot is ~30GB compressed and needs ~30GB more for extraction"
        exit 1
    fi
    
    print_status "Downloading: $LATEST (~30GB)"
    
    # Install aria2c for faster downloads if not present
    if ! command -v aria2c >/dev/null 2>&1 && ! command -v axel >/dev/null 2>&1; then
        print_status "Installing download accelerators for faster speeds..."
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y aria2 axel >/dev/null 2>&1 || true
    fi
    
    # Install bc for speed calculations if not present
    if ! command -v bc >/dev/null 2>&1; then
        sudo apt-get install -y bc >/dev/null 2>&1 || true
    fi
    
    # Try different download methods for better speed
    DOWNLOAD_SUCCESS=false
    
    if command -v aria2c >/dev/null 2>&1; then
        print_status "Using aria2c for faster multi-connection download..."
        
        # Try up to 3 times with different connection counts
        for attempt in 1 2 3; do
            case $attempt in
                1) CONNECTIONS=16; SPLITS=16 ;;  # Try aggressive first
                2) CONNECTIONS=8; SPLITS=8 ;;     # Then moderate
                3) CONNECTIONS=4; SPLITS=4 ;;     # Then conservative
            esac
            
            print_status "Download attempt $attempt of 3 (using $CONNECTIONS connections)..."
            
            # Create a wrapper script to monitor speed
            cat > /tmp/download_with_timeout.sh << 'EOFD'
#!/bin/bash
LOGFILE="/tmp/aria2c_speed.log"
PID_FILE="/tmp/aria2c.pid"
MIN_SPEED_MB=1  # Minimum acceptable speed in MB/s
CHECK_AFTER=30  # Start checking speed after 30 seconds

# Start aria2c in background and capture its PID
aria2c "$@" 2>&1 | tee $LOGFILE &
ARIA_PID=$!
echo $ARIA_PID > $PID_FILE

# Let it stabilize for initial period
sleep $CHECK_AFTER

# Monitor speed
SLOW_COUNT=0
while kill -0 $ARIA_PID 2>/dev/null; do
    # Extract current speed from aria2c output
    CURRENT_SPEED=$(tail -n 5 $LOGFILE | grep -oP 'DL:[\d.]+[KMG]iB' | tail -1 | grep -oP '[\d.]+[KMG]' | tail -1)
    
    if [ -n "$CURRENT_SPEED" ]; then
        # Convert to MB/s for comparison
        UNIT=$(echo $CURRENT_SPEED | grep -oP '[KMG]')
        SPEED_VAL=$(echo $CURRENT_SPEED | grep -oP '[\d.]+')
        
        case $UNIT in
            K) SPEED_MB=$(echo "$SPEED_VAL / 1024" | bc -l) ;;
            M) SPEED_MB=$SPEED_VAL ;;
            G) SPEED_MB=$(echo "$SPEED_VAL * 1024" | bc -l) ;;
            *) SPEED_MB=0 ;;
        esac
        
        # Check if speed is too slow
        if (( $(echo "$SPEED_MB < $MIN_SPEED_MB" | bc -l) )); then
            SLOW_COUNT=$((SLOW_COUNT + 1))
            if [ $SLOW_COUNT -ge 3 ]; then
                echo "Speed too slow ($CURRENT_SPEED), killing download..."
                kill $ARIA_PID 2>/dev/null
                exit 1
            fi
        else
            SLOW_COUNT=0  # Reset if speed is good
        fi
    fi
    sleep 10
done

wait $ARIA_PID
EXIT_CODE=$?
rm -f $LOGFILE $PID_FILE
exit $EXIT_CODE
EOFD
            chmod +x /tmp/download_with_timeout.sh
            
            # Run download with monitoring
            if /tmp/download_with_timeout.sh \
                   -x $CONNECTIONS -s $SPLITS -k 10M \
                   --min-split-size=10M \
                   --max-connection-per-server=$CONNECTIONS \
                   --file-allocation=falloc \
                   --max-tries=5 \
                   --retry-wait=5 \
                   --continue=true \
                   --auto-file-renaming=false \
                   --allow-overwrite=true \
                   --console-log-level=warn \
                   --summary-interval=10 \
                   --human-readable=true \
                   --max-download-limit=0 \
                   --disable-ipv6=true \
                   --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                   --timeout=60 \
                   --connect-timeout=60 \
                   --lowest-speed-limit=1M \
                   -o $LATEST \
                   https://backup.koinosblocks.com/$LATEST; then
                DOWNLOAD_SUCCESS=true
                print_success "Download completed successfully!"
                break
            else
                print_warning "Download attempt $attempt failed or was too slow"
                
                # If file exists and is substantial, check if we should continue
                if [ -f "$LATEST" ]; then
                    CURRENT_SIZE=$(stat -c%s "$LATEST" 2>/dev/null || stat -f%z "$LATEST" 2>/dev/null || echo 0)
                    EXPECTED_SIZE=$((30 * 1024 * 1024 * 1024))  # ~30GB
                    
                    if [ "$CURRENT_SIZE" -gt $((EXPECTED_SIZE * 8 / 10)) ]; then
                        print_status "Download is 80% complete, continuing with current file..."
                        continue
                    else
                        print_status "Partial download is only $(($CURRENT_SIZE / 1024 / 1024))MB, retrying..."
                        rm -f $LATEST
                        # Wait a bit before retry
                        sleep 5
                    fi
                fi
            fi
        done
        
        rm -f /tmp/download_with_timeout.sh
    fi
    
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        if command -v axel >/dev/null 2>&1; then
            print_status "Trying axel for multi-connection download..."
            if axel -n 8 -a -o $LATEST https://backup.koinosblocks.com/$LATEST; then
                DOWNLOAD_SUCCESS=true
            else
                rm -f $LATEST
            fi
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        if command -v curl >/dev/null 2>&1; then
            print_status "Trying curl for download..."
            if curl -L --progress-bar \
                 --retry 3 \
                 --retry-delay 5 \
                 --max-time 7200 \
                 -o $LATEST \
                 https://backup.koinosblocks.com/$LATEST; then
                DOWNLOAD_SUCCESS=true
            else
                rm -f $LATEST
            fi
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        print_status "Using wget as final fallback..."
        wget --progress=bar:force \
             --tries=3 \
             --timeout=60 \
             --continue \
             https://backup.koinosblocks.com/$LATEST -O $LATEST
        DOWNLOAD_SUCCESS=true
    fi
    
    # Verify download completed
    if [ ! -f "$LATEST" ]; then
        print_error "Download failed - file not found"
        exit 1
    fi
    
    print_status "Extracting snapshot (this will use additional ~30GB temporarily)..."
    
    # Get total size for progress tracking
    ARCHIVE_SIZE=$(stat -c%s "$LATEST" 2>/dev/null || stat -f%z "$LATEST" 2>/dev/null)
    
    # Install pv for progress monitoring if not available
    if ! command -v pv >/dev/null 2>&1; then
        print_status "Installing 'pv' for extraction progress monitoring..."
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y pv >/dev/null 2>&1
    fi
    
    # Extract with progress indicator using pv if available, otherwise use verbose tar
    if command -v pv >/dev/null 2>&1; then
        print_status "Extracting with progress indicator..."
        # Show progress with size, timer, rate, and ETA
        if ! pv -petrab $LATEST | tar -xzf -; then
            print_error "Failed to extract snapshot"
            rm -f $LATEST  # Clean up on extraction failure
            exit 1
        fi
    else
        print_status "Extracting (unable to show progress bar)..."
        # Use verbose mode to show files being extracted
        if ! tar -xzvf $LATEST | while read -r line; do
            # Show a dot every 100 files for basic progress indication
            COUNT=$((COUNT + 1))
            if [ $((COUNT % 100)) -eq 0 ]; then
                echo -n "."
            fi
            if [ $((COUNT % 5000)) -eq 0 ]; then
                echo " ($COUNT files extracted)"
            fi
        done; then
            print_error "Failed to extract snapshot"
            rm -f $LATEST  # Clean up on extraction failure
            exit 1
        fi
        echo  # New line after dots
    fi
    
    print_status "Cleaning up archive to free ~30GB..."
    rm -f $LATEST  # Delete archive immediately after extraction to save space
    
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
    
    print_success "Blockchain snapshot installed and archive cleaned up"
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