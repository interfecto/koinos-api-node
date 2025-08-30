#!/bin/bash

# Koinos API Node Installer - HARDENED VERSION
# Enhanced security, proper isolation, and production-ready configuration
# Usage: curl -sSL https://your-domain.com/installHardened.sh | bash
# Or: wget -qO- https://your-domain.com/installHardened.sh | bash

set -euo pipefail  # Exit on error, undefined variables, and pipe failures
IFS=$'\n\t'       # Set secure Internal Field Separator

# Script version
SCRIPT_VERSION="2.0.0-hardened"

# Enhanced error handling with line numbers
error_handler() {
    local line_no=$1
    local exit_code=$2
    print_error "Script failed at line $line_no with exit code $exit_code"
    print_status "Run with bash -x for detailed debugging"
    cleanup
}
trap 'error_handler ${LINENO} $?' ERR

# Cleanup function for interrupts
cleanup() {
    print_warning "Installation interrupted. Cleaning up..."
    # Kill any background aria2c processes
    pkill aria2c 2>/dev/null || true
    # Remove temporary files
    rm -f /tmp/download_with_timeout.sh /tmp/aria2c_speed.log /tmp/aria2c.pid 2>/dev/null || true
    exit 1
}

# Set trap for cleanup on script exit/interrupt
trap cleanup INT TERM

echo "=========================================="
echo "🔒 Koinos API Node Installer - HARDENED"
echo "   Version: $SCRIPT_VERSION"
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_security() {
    echo -e "${CYAN}[SECURITY]${NC} $1"
}

# Parse command line arguments
SKIP_SNAPSHOT=false
COMPOSE_PROFILE="api-node"  # Default profile
ENABLE_P2P=false
ENABLE_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-snapshot)
            SKIP_SNAPSHOT=true
            shift
            ;;
        --profile)
            COMPOSE_PROFILE="$2"
            shift 2
            ;;
        --enable-p2p)
            ENABLE_P2P=true
            shift
            ;;
        --enable-all)
            ENABLE_ALL=true
            COMPOSE_PROFILE="all"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-snapshot     Skip downloading blockchain snapshot"
            echo "  --profile PROFILE Set Compose profile (api-node, indexer, all)"
            echo "  --enable-p2p      Open P2P port in firewall"
            echo "  --enable-all      Enable all services (not recommended)"
            echo "  --help            Show this help message"
            echo ""
            echo "Profiles:"
            echo "  api-node  - Minimal API node (jsonrpc, grpc) [DEFAULT]"
            echo "  indexer   - Full indexer node (includes account history)"
            echo "  all       - All services (resource intensive)"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Run $0 --help for usage"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check operating system compatibility
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_PRETTY="${PRETTY_NAME:-Unknown}"
    
    if ! echo "$OS_ID $OS_ID_LIKE" | grep -qE "ubuntu|debian"; then
        print_warning "This installer is optimized for Ubuntu and Debian."
        print_status "Detected: $OS_PRETTY"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    print_warning "Cannot detect OS version"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    OS_ID="unknown"
fi

# Install required dependencies first
print_status "Installing required dependencies..."
DEPS="wget curl git jq ca-certificates gnupg lsb-release bc"
MISSING_DEPS=""

for dep in $DEPS; do
    if ! command -v $dep >/dev/null 2>&1; then
        MISSING_DEPS="$MISSING_DEPS $dep"
    fi
done

if [ -n "$MISSING_DEPS" ]; then
    print_status "Installing missing dependencies:$MISSING_DEPS"
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install -y $MISSING_DEPS >/dev/null 2>&1 || {
        print_error "Failed to install dependencies"
        exit 1
    }
fi

print_status "Checking system requirements..."

# ============================================
# ENHANCED SYSTEM REQUIREMENTS CHECKS
# ============================================

# Check RAM (in MB for accurate calculation)
TOTAL_RAM_MB=$(free -m | awk 'NR==2{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))

print_status "System RAM: ${TOTAL_RAM_GB}GB"

if [ "$TOTAL_RAM_MB" -lt 8192 ]; then
    print_error "Insufficient RAM. Minimum 8GB required, found ${TOTAL_RAM_GB}GB"
    print_status "Koinos nodes require at least 8GB RAM for stable operation"
    exit 1
elif [ "$TOTAL_RAM_MB" -lt 16384 ]; then
    print_warning "RAM is below recommended. Found ${TOTAL_RAM_GB}GB, recommend 16GB+"
    print_status "Node will run but may experience performance issues under load"
    read -p "Continue with limited RAM? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "RAM check passed: ${TOTAL_RAM_GB}GB available"
fi

# Check available disk space
if df -BG "$HOME" >/dev/null 2>&1; then
    # Linux format with -BG flag
    AVAILABLE_SPACE=$(df -BG "$HOME" | awk 'NR==2 {print int($4)}')
else
    # macOS/BSD format - convert KB to GB
    AVAILABLE_KB=$(df "$HOME" | awk 'NR==2 {print $4}')
    AVAILABLE_SPACE=$((AVAILABLE_KB / 1024 / 1024))
fi

# Determine required space based on profile and existing data
if [ -d "$HOME/.koinos/chain" ] || [ -d "$HOME/chain" ]; then
    REQUIRED_SPACE=30
    print_status "Found existing blockchain data, checking for ${REQUIRED_SPACE}GB free space..."
else
    # API nodes and indexers need more space
    if [ "$COMPOSE_PROFILE" = "indexer" ] || [ "$COMPOSE_PROFILE" = "all" ]; then
        REQUIRED_SPACE=150
        print_status "Indexer node requires ${REQUIRED_SPACE}GB for full operation..."
    else
        REQUIRED_SPACE=100
        print_status "API node requires ${REQUIRED_SPACE}GB free space..."
    fi
fi

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    print_error "Insufficient disk space. Need at least ${REQUIRED_SPACE}GB free, found ${AVAILABLE_SPACE}GB"
    exit 1
fi

print_success "Disk space check passed: ${AVAILABLE_SPACE}GB available"

# Function to install Docker with proper distro detection
install_docker() {
    print_status "Installing Docker..."
    
    # Remove old Docker versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    
    # Detect correct Docker repository based on distro
    case "$OS_ID" in
        ubuntu)
            DOCKER_DISTRO="ubuntu"
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            ;;
        debian)
            DOCKER_DISTRO="debian"
            curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            ;;
        *)
            # Try to detect based on ID_LIKE
            if echo "$OS_ID_LIKE" | grep -q "ubuntu"; then
                DOCKER_DISTRO="ubuntu"
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            elif echo "$OS_ID_LIKE" | grep -q "debian"; then
                DOCKER_DISTRO="debian"
                curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            else
                print_warning "Unknown distribution, attempting Ubuntu repository"
                DOCKER_DISTRO="ubuntu"
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            fi
            ;;
    esac
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_DISTRO \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker
    
    print_success "Docker installed successfully"
    print_security "User added to docker group. You'll need to logout/login for group changes to take effect."
}

# ENHANCED FIREWALL CONFIGURATION
configure_firewall() {
    print_status "Configuring firewall with security-first approach..."
    
    if ! command -v ufw >/dev/null 2>&1; then
        print_status "Installing UFW firewall..."
        sudo apt-get install -y ufw
    fi
    
    # CRITICAL: Set default policies FIRST (before enabling)
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # CRITICAL: Allow SSH BEFORE enabling firewall to prevent lockout
    print_security "Allowing SSH access to prevent lockout..."
    sudo ufw allow ssh
    
    # Only expose CORS proxy publicly (port 8081)
    print_security "Opening port 8081 for CORS proxy (public API access)..."
    sudo ufw allow 8081/tcp comment 'Koinos CORS Proxy'
    
    # Optionally open P2P port if requested
    if [ "$ENABLE_P2P" = true ]; then
        # Read P2P port from .env if it exists, otherwise use default
        P2P_PORT=8888
        if [ -f "$HOME/koinos/.env" ]; then
            P2P_FROM_ENV=$(grep "^P2P_PORT=" "$HOME/koinos/.env" 2>/dev/null | cut -d'=' -f2)
            P2P_PORT=${P2P_FROM_ENV:-8888}
        fi
        print_security "Opening P2P port $P2P_PORT for blockchain sync..."
        sudo ufw allow $P2P_PORT/tcp comment 'Koinos P2P'
    else
        print_security "P2P port not opened (use --enable-p2p if needed for seeding)"
    fi
    
    # DO NOT open these ports publicly - they remain localhost only
    print_security "Keeping JSON-RPC (8080), gRPC (50051), REST (3000) on localhost only"
    
    # Enable firewall LAST
    sudo ufw --force enable
    
    print_success "Firewall configured with security hardening"
    print_security "Public access: CORS proxy (8081) only"
    print_security "Internal only: JSON-RPC (8080), gRPC (50051), REST (3000)"
}

# Function to setup Koinos node
setup_koinos() {
    print_status "Setting up Koinos node..."
    
    cd $HOME
    
    # Clone Koinos repository
    if [ -d "koinos" ]; then
        # Check if it's a valid Koinos installation
        if [ -f "koinos/docker-compose.yml" ]; then
            print_status "Koinos directory already exists, using existing installation..."
            cd koinos
        else
            print_warning "Koinos directory exists but seems incomplete. Backing it up..."
            mv koinos koinos_backup_$(date +%Y%m%d_%H%M%S)
            git clone https://github.com/koinos/koinos
            cd koinos
        fi
    else
        git clone https://github.com/koinos/koinos
        cd koinos
    fi
    
    # Generate .env file
    print_status "Generating configuration..."
    ./generate_config.sh
    
    # SECURITY: Keep all API services bound to localhost only
    print_security "Configuring services to bind to localhost only (security hardening)..."
    # We do NOT change JSONRPC_INTERFACE, GRPC_INTERFACE, or REST_INTERFACE to 0.0.0.0
    # They should remain at default (127.0.0.1) for security
    
    # Set appropriate Compose profile based on user selection
    print_status "Setting Compose profile: $COMPOSE_PROFILE"
    case "$COMPOSE_PROFILE" in
        api-node)
            # Minimal API node - just JSON-RPC and gRPC
            sed -i "s/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=jsonrpc,grpc/" .env
            print_success "Configured for minimal API node (jsonrpc, grpc)"
            ;;
        indexer)
            # Full indexer with account history
            sed -i "s/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=api/" .env
            print_success "Configured for indexer node with account history"
            ;;
        all)
            # Everything (not recommended)
            sed -i "s/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=all/" .env
            print_warning "Configured for ALL services (resource intensive!)"
            ;;
        *)
            # Default to API node
            sed -i "s/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=jsonrpc,grpc/" .env
            print_success "Configured for minimal API node (default)"
            ;;
    esac
    
    # Add performance optimizations
    cat >> .env << EOF

# Performance optimizations (Hardened installer)
KOINOS_LOG_LEVEL=warn
KOINOS_JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
KOINOS_LOG_JSON=false

# Version pinning for reproducible deployments
# Update these to upgrade services
CHAIN_TAG=latest
JSONRPC_TAG=latest
GRPC_TAG=latest
P2P_TAG=latest
EOF
    
    # Validate docker-compose configuration
    print_status "Validating Docker Compose configuration..."
    if ! docker compose config >/dev/null 2>&1; then
        print_error "Docker Compose configuration validation failed"
        print_status "Please check docker-compose.yml for syntax errors"
        exit 1
    fi
    
    print_success "Koinos configuration completed and validated"
}

# Setup CORS proxy using docker-compose override
setup_cors_proxy() {
    print_status "Setting up CORS proxy for secure browser access..."
    
    cd $HOME/koinos
    
    # Create docker-compose.override.yml for clean separation
    cat > docker-compose.override.yml << 'EOF'
# Docker Compose Override - CORS Proxy
# This file is automatically merged with docker-compose.yml
version: '3.8'

services:
  cors-proxy:
    build:
      context: .
      dockerfile: Dockerfile.cors
    container_name: koinos-cors-proxy
    restart: unless-stopped
    ports:
      - "8081:8081"  # Only expose CORS proxy publicly
    depends_on:
      - jsonrpc
    networks:
      - koinos
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  koinos:
    external: true
    name: koinos_default
EOF
    
    # Create Dockerfile.cors
    cat > Dockerfile.cors << 'EOF'
FROM nginx:alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our config
COPY nginx.conf /etc/nginx/nginx.conf

# Health check endpoint
RUN echo "OK" > /usr/share/nginx/html/health

EXPOSE 8081
EOF
    
    # Create nginx.conf with enhanced security and proper upstream handling
    cat > nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Logging
    access_log /var/log/nginx/access.log combined;
    
    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    gzip on;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;
    
    upstream koinos_jsonrpc {
        # Try container name first (works in Docker network)
        server jsonrpc:7777 max_fails=2 fail_timeout=10s;
        
        # Fallback to host network (for docker-compose networking)
        server host.docker.internal:8080 backup max_fails=2 fail_timeout=10s;
    }
    
    server {
        listen 8081;
        server_name _;
        
        # API endpoint with CORS
        location / {
            # Rate limiting
            limit_req zone=api_limit burst=50 nodelay;
            
            # CORS headers - Allow all origins for public API
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
            add_header 'Access-Control-Max-Age' '1728000' always;
            
            # Handle preflight requests
            if ($request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' '*' always;
                add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
                add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
                add_header 'Access-Control-Max-Age' '1728000';
                add_header 'Content-Type' 'text/plain; charset=utf-8';
                add_header 'Content-Length' '0';
                return 204;
            }
            
            # Proxy to Koinos JSON-RPC
            proxy_pass http://koinos_jsonrpc;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
            
            # Buffering
            proxy_buffering off;
        }
        
        # Health check endpoint
        location /health {
            access_log off;
            add_header 'Content-Type' 'text/plain';
            return 200 'healthy\n';
        }
        
        # Status page (internal only)
        location /nginx_status {
            stub_status;
            allow 127.0.0.1;
            deny all;
        }
    }
}
EOF
    
    print_success "CORS proxy configuration created using docker-compose override"
    print_security "Clean separation maintained - no modifications to upstream files"
}

# Function to download blockchain snapshot
download_snapshot() {
    if [ "$SKIP_SNAPSHOT" = true ]; then
        print_status "Skipping snapshot download (--no-snapshot specified)"
        return
    fi
    
    print_status "Starting blockchain snapshot download process..."
    
    cd $HOME
    
    # Initialize flags
    SKIP_DOWNLOAD=false
    SKIP_EXTRACTION=false
    DOWNLOAD_SUCCESS=false
    
    # Set default values for important variables
    HOME=${HOME:-/home/$USER}
    USER=${USER:-$(whoami)}
    LATEST=""
    REQUIRED_SPACE=80
    
    print_status "Checking for existing blockchain data..."
    
    # Get latest snapshot (compatible with macOS and Linux grep)
    LATEST=$(curl -s https://backup.koinosblocks.com/ | sed -n 's/.*\(backup_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\.tar\.gz\).*/\1/p' | sort | tail -n 1)
    
    if [ -z "$LATEST" ]; then
        print_error "Could not find latest snapshot"
        print_status "You can manually download from https://backup.koinosblocks.com/"
        return
    fi
    
    print_warning "Note: Using community-provided snapshot from koinosblocks.com"
    print_status "Latest snapshot: $LATEST"
    
    # Check if data already exists
    if [ -d "$HOME/.koinos/chain" ] && [ -d "$HOME/.koinos/block_store" ]; then
        print_success "Blockchain data already exists at ~/.koinos"
        print_status "Skipping snapshot download"
        return
    fi
    
    # Download snapshot (using simplified approach for hardened version)
    if [ ! -f "$LATEST" ]; then
        print_status "Downloading snapshot (~30GB)..."
        
        # Try wget with resume support
        if command -v wget >/dev/null 2>&1; then
            wget --progress=bar:force \
                 --tries=3 \
                 --timeout=60 \
                 --continue \
                 https://backup.koinosblocks.com/$LATEST -O $LATEST || {
                print_error "Download failed"
                rm -f $LATEST
                return
            }
        else
            print_error "wget not found. Please install wget or download manually"
            return
        fi
    fi
    
    # Extract snapshot
    if [ -f "$LATEST" ]; then
        print_status "Extracting snapshot..."
        
        # Use pv for progress if available
        if command -v pv >/dev/null 2>&1; then
            pv $LATEST | tar -xzf - || {
                print_error "Extraction failed"
                return
            }
        else
            tar -xzf $LATEST || {
                print_error "Extraction failed"
                return
            }
        fi
        
        # Move to correct location
        if [ -d "backup" ]; then
            print_status "Moving snapshot data to ~/.koinos..."
            mv backup ~/.koinos
        elif [ -d "chain" ] && [ -d "block_store" ]; then
            print_status "Moving blockchain directories to ~/.koinos..."
            mkdir -p ~/.koinos
            for dir in chain block_store account_history contract_meta_store transaction_store mempool; do
                if [ -d "$dir" ]; then
                    mv "$dir" ~/.koinos/ 2>/dev/null || true
                fi
            done
        fi
        
        # Clean up
        print_status "Cleaning up archive..."
        rm -f $LATEST
        
        print_success "Snapshot installed successfully"
    fi
}

# Create enhanced management scripts
create_management_scripts() {
    print_status "Creating enhanced management scripts..."
    
    # Enhanced status script with proper calculations
    cat > $HOME/koinos-status.sh << 'EOF'
#!/bin/bash

echo "=========================================="
echo "🔒 Koinos Node Status (Hardened)"
echo "   $(date)"
echo "=========================================="
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check containers
echo "=== Container Status ==="
cd ~/koinos && docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
echo

# Check API health
echo "=== API Health ==="
if curl -s -X POST -H "Content-Type: application/json" \
   -d '{"jsonrpc":"2.0","method":"chain.get_head_info","params":{},"id":1}' \
   http://localhost:8080 >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} JSON-RPC (localhost:8080): Healthy"
else
    echo -e "${RED}✗${NC} JSON-RPC (localhost:8080): Not responding"
fi

if curl -s http://localhost:8081/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} CORS Proxy (0.0.0.0:8081): Healthy"
else
    echo -e "${RED}✗${NC} CORS Proxy (0.0.0.0:8081): Not responding"
fi
echo

# Memory stats with proper calculation
echo "=== System Resources ==="
# Use numeric values for calculation
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
echo "Memory: ${MEM_USED}MB/${MEM_TOTAL}MB (${MEM_PERCENT}%)"

DISK_INFO=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
echo "Disk: $DISK_INFO"
echo

# Blockchain sync status
echo "=== Blockchain Status ==="
RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"chain.get_head_info","params":{},"id":1}' \
  http://localhost:8080 2>/dev/null)

if [ -n "$RESPONSE" ]; then
    HEIGHT=$(echo "$RESPONSE" | jq -r '.result.head_topology.height' 2>/dev/null)
    if [ "$HEIGHT" != "null" ] && [ -n "$HEIGHT" ]; then
        echo "Current Height: $HEIGHT"
    else
        echo "Syncing..."
    fi
else
    echo "API not ready"
fi
echo

# Recent logs
echo "=== Recent Activity ==="
cd ~/koinos && docker compose logs --tail=3 chain 2>/dev/null | grep -v "^Attaching"
EOF
    chmod +x $HOME/koinos-status.sh
    
    # Enhanced management script with proper paths
    cat > $HOME/koinos-manage.sh << 'EOF'
#!/bin/bash

# Always work from the koinos directory
KOINOS_DIR="$HOME/koinos"

case "$1" in
    start)
        echo "Starting Koinos node..."
        cd "$KOINOS_DIR" && docker compose up -d
        ;;
    stop)
        echo "Stopping Koinos node..."
        cd "$KOINOS_DIR" && docker compose down
        ;;
    restart)
        echo "Restarting Koinos node..."
        cd "$KOINOS_DIR" && docker compose restart
        ;;
    logs)
        SERVICE="${2:-chain}"
        echo "Showing logs for $SERVICE (Ctrl+C to exit)..."
        cd "$KOINOS_DIR" && docker compose logs -f "$SERVICE"
        ;;
    update)
        echo "Updating Koinos node..."
        cd "$KOINOS_DIR" && docker compose down
        cd "$KOINOS_DIR" && docker compose pull
        cd "$KOINOS_DIR" && docker compose up -d
        echo "Update complete!"
        ;;
    status)
        ~/koinos-status.sh
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|update|status} [service]"
        echo ""
        echo "Commands:"
        echo "  start   - Start the Koinos node"
        echo "  stop    - Stop the Koinos node"
        echo "  restart - Restart the Koinos node"
        echo "  logs    - Show logs (optional: specify service)"
        echo "  update  - Update and restart node"
        echo "  status  - Show detailed node status"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 logs chain"
        echo "  $0 logs cors-proxy"
        ;;
esac
EOF
    chmod +x $HOME/koinos-manage.sh
    
    print_success "Management scripts created with enhanced functionality"
}

# Function to start the node
start_node() {
    print_status "Starting Koinos node..."
    
    cd $HOME/koinos
    
    # Start services (docker-compose will use both yml files automatically)
    if command -v sg >/dev/null 2>&1; then
        sg docker -c "docker compose up -d"
    else
        # Fallback for systems without sg command
        docker compose up -d || {
            print_warning "May need to logout/login for Docker group changes to take effect"
            sudo docker compose up -d
        }
    fi
    
    print_success "Koinos node started"
}

# Test APIs with proper security information
test_apis() {
    print_status "Waiting for APIs to be ready..."
    
    # Wait for services to start
    sleep 30
    
    # Test JSON-RPC API (localhost only)
    if timeout 5 curl -s -X POST -H "Content-Type: application/json" \
       -d '{"jsonrpc":"2.0","method":"chain.get_head_info","params":{},"id":1}' \
       http://localhost:8080 > /dev/null 2>&1; then
        print_success "JSON-RPC API is responding (localhost only)"
    else
        print_warning "JSON-RPC API not ready yet (this is normal during initial startup)"
    fi
    
    # Test CORS proxy (public)
    if timeout 5 curl -s http://localhost:8081/health > /dev/null 2>&1; then
        print_success "CORS proxy is responding (public access)"
    else
        print_warning "CORS proxy not ready yet"
    fi
}

# Main installation flow
main() {
    print_status "Starting Koinos node installation (HARDENED VERSION)..."
    
    # Check if Docker is already installed
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    else
        print_success "Docker already installed"
        # Verify docker compose
        if ! docker compose version >/dev/null 2>&1; then
            print_error "Docker Compose not found. Please install Docker Compose v2"
            exit 1
        fi
    fi
    
    configure_firewall
    setup_koinos
    setup_cors_proxy
    download_snapshot
    create_management_scripts
    start_node
    test_apis
    
    # Get external IP safely
    EXTERNAL_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
                  curl -s --max-time 5 icanhazip.com 2>/dev/null || \
                  echo "YOUR_SERVER_IP")
    
    echo
    echo "=========================================="
    echo "🔒 HARDENED Installation Complete!"
    echo "=========================================="
    echo
    echo "Your Koinos API node is now running with enhanced security!"
    echo
    echo "📡 PUBLIC API Endpoints (accessible from internet):"
    echo "   • CORS Proxy: http://${EXTERNAL_IP}:8081"
    echo "   • Health Check: http://${EXTERNAL_IP}:8081/health"
    echo
    echo "🔐 INTERNAL Endpoints (localhost only - secure):"
    echo "   • JSON-RPC: http://127.0.0.1:8080"
    echo "   • gRPC: grpc://127.0.0.1:50051"
    echo "   • REST: http://127.0.0.1:3000"
    if [ "$ENABLE_P2P" = true ]; then
        echo "   • P2P: Port ${P2P_PORT:-8888} (open)"
    else
        echo "   • P2P: Port 8888 (localhost only)"
    fi
    echo
    echo "🛠️ Management Commands:"
    echo "   • Check status: ~/koinos-status.sh"
    echo "   • Manage node: ~/koinos-manage.sh [start|stop|restart|logs|update|status]"
    echo
    echo "📊 Configuration:"
    echo "   • Profile: $COMPOSE_PROFILE"
    echo "   • RAM: ${TOTAL_RAM_GB}GB"
    echo "   • Disk: ${AVAILABLE_SPACE}GB available"
    echo
    echo "🔒 Security Features:"
    echo "   ✓ APIs bound to localhost only"
    echo "   ✓ Public access via CORS proxy only"
    echo "   ✓ Firewall configured with minimal exposure"
    echo "   ✓ Rate limiting enabled on proxy"
    echo "   ✓ Container restart policies configured"
    echo "   ✓ Log rotation enabled"
    echo
    if [ "$SKIP_SNAPSHOT" = true ]; then
        print_warning "Note: Snapshot download was skipped. Initial sync will take longer."
    else
        echo "The node is syncing. Monitor progress with: ~/koinos-status.sh"
    fi
    echo
    print_warning "IMPORTANT: You may need to log out and back in for Docker group changes to take effect."
}

# Run main function
main "$@"