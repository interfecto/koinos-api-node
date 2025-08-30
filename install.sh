#!/bin/bash

# Koinos API Node Installer
# Usage: curl -sSL https://your-domain.com/install-koinos.sh | bash
# Or: wget -qO- https://your-domain.com/install-koinos.sh | bash

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

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

# Install essential dependencies if missing
ESSENTIAL_DEPS="curl wget git"
MISSING=""
for dep in $ESSENTIAL_DEPS; do
    if ! command -v $dep >/dev/null 2>&1; then
        MISSING="$MISSING $dep"
    fi
done

if [ -n "$MISSING" ]; then
    print_status "Installing essential dependencies:$MISSING"
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install -y $MISSING >/dev/null 2>&1 || {
        print_warning "Could not install some dependencies"
    }
fi

# Check operating system compatibility
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if ! echo "$ID $ID_LIKE" | grep -qE "ubuntu|debian"; then
        print_warning "This installer is optimized for Ubuntu and Debian."
        print_status "Detected: ${PRETTY_NAME:-Unknown}"
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
fi

print_status "Checking system requirements..."

# Check RAM (important for node stability)
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk 'NR==2{print $2}' || echo "8192")
TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))

if [ "$TOTAL_RAM_MB" -lt 4096 ]; then
    print_error "Insufficient RAM. Minimum 4GB required, found ${TOTAL_RAM_GB}GB"
    print_status "Koinos nodes need at least 4GB RAM to run"
    exit 1
elif [ "$TOTAL_RAM_MB" -lt 8192 ]; then
    print_warning "Low RAM detected: ${TOTAL_RAM_GB}GB. Recommended: 8GB+"
    print_status "Node will run but may be slow under load"
else
    print_success "RAM check passed: ${TOTAL_RAM_GB}GB available"
fi

# Check available disk space - be smart about requirements
AVAILABLE_SPACE=$(df "$HOME" 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}' || df / | awk 'NR==2 {print int($4/1024/1024)}')

# Make sure we got a valid number
if [ -z "$AVAILABLE_SPACE" ] || [ "$AVAILABLE_SPACE" -eq 0 ]; then
    print_warning "Could not determine available disk space, continuing anyway..."
    AVAILABLE_SPACE=999999  # Set to large number to skip check
fi

# Check if blockchain data already exists (then we need less space)
if [ -d "$HOME/.koinos/chain" ] || [ -d "$HOME/chain" ]; then
    # Data exists, only need space for Docker operations
    REQUIRED_SPACE=30
    print_status "Found existing blockchain data, checking for ${REQUIRED_SPACE}GB free space..."
else
    # Need space for download + extraction + final data
    REQUIRED_SPACE=80  # Reduced from 100 since we delete archive immediately after extraction
    print_status "No blockchain data found, checking for ${REQUIRED_SPACE}GB free space for full installation..."
fi

if [ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]; then
    print_error "Insufficient disk space. Need at least ${REQUIRED_SPACE}GB free, found ${AVAILABLE_SPACE}GB"
    if [ $REQUIRED_SPACE -eq 80 ]; then
        print_status "Tip: 80GB needed for: 30GB download + 30GB extraction + 30GB final data"
        print_status "Note: Archive is deleted immediately after extraction to save space"
    else
        print_status "Tip: Since you have existing data, only ${REQUIRED_SPACE}GB needed for Docker operations"
    fi
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
    
    # Add Docker repository (detect Ubuntu vs Debian)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu)
                DOCKER_DISTRO="ubuntu"
                ;;
            debian)
                DOCKER_DISTRO="debian"
                ;;
            *)
                # Try to detect based on ID_LIKE
                if echo "$ID_LIKE" | grep -q "ubuntu"; then
                    DOCKER_DISTRO="ubuntu"
                elif echo "$ID_LIKE" | grep -q "debian"; then
                    DOCKER_DISTRO="debian"
                else
                    print_warning "Unknown distribution, defaulting to Ubuntu repository"
                    DOCKER_DISTRO="ubuntu"
                fi
                ;;
        esac
    else
        DOCKER_DISTRO="ubuntu"
    fi
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_DISTRO \
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
        # CRITICAL: Set default policies FIRST (before enabling)
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        # CRITICAL: Allow SSH BEFORE enabling firewall to prevent lockout!
        print_status "Allowing SSH to prevent lockout..."
        sudo ufw allow ssh
        
        # Allow Koinos ports
        sudo ufw allow 8080/tcp comment 'Koinos JSON-RPC'
        sudo ufw allow 8081/tcp comment 'Koinos CORS Proxy'
        sudo ufw allow 8888/tcp comment 'Koinos P2P'
        sudo ufw allow 50051/tcp comment 'Koinos gRPC'
        
        # Enable firewall LAST (after SSH is allowed)
        sudo ufw --force enable
        
        print_success "Firewall configured safely"
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
KOINOS_JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
KOINOS_LOG_JSON=false
EOF
    
    print_success "Koinos configuration completed"
}

# Function to setup CORS proxy as a separate Docker container
setup_cors_proxy() {
    print_status "Setting up CORS proxy for browser access..."
    
    # Create a separate directory for CORS proxy
    mkdir -p ~/koinos-cors-proxy
    cd ~/koinos-cors-proxy
    
    # Create Dockerfile for CORS proxy
    cat > Dockerfile << 'EOF'
FROM nginx:alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
EOF
    
    # Create nginx configuration with CORS headers
    cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream koinos_jsonrpc {
        # Use host.docker.internal for Docker Desktop, fallback to bridge IP for Linux
        server host.docker.internal:8080 max_fails=2 fail_timeout=10s;
        # Backup: direct bridge network IP (will be ignored if first works)
        server 172.17.0.1:8080 backup max_fails=2 fail_timeout=10s;
    }
    
    server {
        listen 8081;
        
        location / {
            # CORS headers
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
            
            # Handle preflight requests
            if ($request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' '*';
                add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
                add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Content-Type' 'text/plain; charset=utf-8';
                add_header 'Content-Length' 0;
                return 204;
            }
            
            # Proxy to Koinos JSON-RPC
            proxy_pass http://koinos_jsonrpc;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    # Create docker-compose.yml for CORS proxy (separate from main Koinos)
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  cors-proxy:
    build: .
    container_name: koinos-cors-proxy
    restart: unless-stopped
    ports:
      - "8081:8081"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    # Build and start the CORS proxy
    print_status "Building CORS proxy container..."
    if docker compose build; then
        print_status "Starting CORS proxy..."
        if docker compose up -d; then
            print_success "CORS proxy started on port 8081"
        else
            print_warning "Failed to start CORS proxy, but node will still work on port 8080"
        fi
    else
        print_warning "Failed to build CORS proxy, but node will still work on port 8080"
    fi
    
    cd ~/koinos
}

# Function to download blockchain snapshot
download_snapshot() {
    print_status "Starting blockchain snapshot download process..."
    
    # Initialize flags FIRST
    SKIP_DOWNLOAD=false
    SKIP_EXTRACTION=false
    DOWNLOAD_SUCCESS=false
    
    # Set default values for important variables
    HOME=${HOME:-/home/$USER}
    USER=${USER:-$(whoami)}
    REQUIRED_SPACE=80
    
    cd $HOME
    
    print_status "Checking for existing checkpoints..."
    
    # Get latest snapshot (compatible with macOS and Linux grep)
    LATEST=$(curl -s https://backup.koinosblocks.com/ | sed -n 's/.*\(backup_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\.tar\.gz\).*/\1/p' | sort | tail -n 1)
    
    if [ -z "$LATEST" ]; then
        print_error "Could not find latest snapshot"
        exit 1
    fi
    
    # Display checkpoint status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 CHECKPOINT STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check download status
    if [ -f "$LATEST" ]; then
        DOWNLOAD_SIZE=$(stat -c%s "$LATEST" 2>/dev/null || stat -f%z "$LATEST" 2>/dev/null || echo 0)
        DOWNLOAD_MB=$((DOWNLOAD_SIZE / 1024 / 1024))
        echo "✓ Download checkpoint: Found ${DOWNLOAD_MB}MB of ~30,000MB"
    else
        echo "✗ Download checkpoint: Not started"
    fi
    
    # Check extraction status
    if [ -d "$HOME/backup" ]; then
        EXTRACT_SIZE=$(du -sm "$HOME/backup" 2>/dev/null | cut -f1)
        echo "✓ Extraction checkpoint: Found ${EXTRACT_SIZE}MB extracted"
    elif [ -d "$HOME/${LATEST%.*.*}" ]; then
        echo "✓ Extraction checkpoint: Complete (alternative directory)"
    else
        echo "✗ Extraction checkpoint: Not started"
    fi
    
    # Check final destination
    if [ -d "$HOME/.koinos" ]; then
        FINAL_SIZE=$(du -sm "$HOME/.koinos" 2>/dev/null | cut -f1)
        echo "✓ Installation checkpoint: Found ${FINAL_SIZE}MB in ~/.koinos"
    else
        echo "✗ Installation checkpoint: Not completed"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Check if we already have the blockchain data in place
    if [ -d "$HOME/.koinos/chain" ] && [ -d "$HOME/.koinos/block_store" ]; then
        print_success "Blockchain data already installed at ~/.koinos, skipping download and extraction!"
        return 0  # Exit the function early
    fi
    
    # Check if we have extracted data that just needs to be moved
    if [ -d "$HOME/chain" ] && [ -d "$HOME/block_store" ]; then
        print_success "Found extracted blockchain data, skipping download!"
        print_status "Moving blockchain directories to ~/.koinos..."
        mkdir -p ~/.koinos
        for dir in chain block_store account_history contract_meta_store transaction_store mempool p2p grpc jsonrpc; do
            if [ -d "$HOME/$dir" ]; then
                print_status "Moving $dir to ~/.koinos/"
                mv "$HOME/$dir" ~/.koinos/ 2>/dev/null || true
            fi
        done
        if [ -f "$HOME/config.yml" ]; then
            mv "$HOME/config.yml" ~/.koinos/ 2>/dev/null || true
        fi
        print_success "Blockchain data organized successfully!"
        return 0  # Exit the function early
    fi
    
    # Only check disk space if we actually need to download
    # Handle both Linux and macOS df output formats
    if df -BG . >/dev/null 2>&1; then
        # Linux format with -BG flag
        AVAILABLE_SPACE=$(df -BG . | awk 'NR==2 {print int($4)}')
    else
        # macOS/BSD format - convert KB to GB
        AVAILABLE_KB=$(df . | awk 'NR==2 {print $4}')
        AVAILABLE_SPACE=$((AVAILABLE_KB / 1024 / 1024))
    fi
    if [ $AVAILABLE_SPACE -lt 60 ]; then
        print_error "Insufficient disk space for snapshot. Need at least 60GB free, found ${AVAILABLE_SPACE}GB"
        print_status "Tip: The snapshot is ~30GB compressed and needs ~30GB more for extraction"
        exit 1
    fi
    
    print_status "Downloading: $LATEST (~30GB)"
    
    # Check if we have a partial download to resume
    if [ -f "$LATEST" ]; then
        EXISTING_SIZE=$(stat -c%s "$LATEST" 2>/dev/null || stat -f%z "$LATEST" 2>/dev/null || echo 0)
        EXISTING_MB=$((EXISTING_SIZE / 1024 / 1024))
        
        if [ "$EXISTING_MB" -gt 100 ]; then
            print_status "Found partial download (${EXISTING_MB}MB), attempting to resume..."
            # Create a backup in case resume fails
            cp "$LATEST" "${LATEST}.backup" 2>/dev/null || true
        else
            print_status "Found small partial file (${EXISTING_MB}MB), removing and starting fresh..."
            rm -f "$LATEST"
        fi
    fi
    
    # Decide what to do based on existing data
    # Priority: 1) Complete data in ~/.koinos 2) Extracted dirs 3) Archive file 4) Nothing
    
    # If we have a backup directory but no archive file, we still need to organize it
    if [ -d "$HOME/backup" ] && [ ! -f "$LATEST" ]; then
        print_status "Found backup directory without archive file, will organize it..."
        SKIP_DOWNLOAD=true  # Don't need to download
        SKIP_EXTRACTION=true  # Already extracted
        DOWNLOAD_SUCCESS=true  # Consider it successful
        # Will move the backup directory later
    elif [ -d "$HOME/chain" ] && [ -d "$HOME/block_store" ] && [ ! -f "$LATEST" ]; then
        print_status "Found extracted blockchain directories without archive, will organize them..."
        SKIP_DOWNLOAD=true
        SKIP_EXTRACTION=true
        DOWNLOAD_SUCCESS=true
        # Will move these directories later
    else
        # Normal download flow - need the archive file
        SKIP_DOWNLOAD=false
        SKIP_EXTRACTION=false
        DOWNLOAD_SUCCESS=false
    fi
    
    # Install aria2c for faster downloads if not present
    if [ "$SKIP_DOWNLOAD" = false ] && ! command -v aria2c >/dev/null 2>&1 && ! command -v axel >/dev/null 2>&1; then
        print_status "Installing download accelerators for faster speeds..."
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y aria2 axel >/dev/null 2>&1 || true
    fi
    
    # Install bc for speed calculations if not present
    if ! command -v bc >/dev/null 2>&1; then
        sudo apt-get install -y bc >/dev/null 2>&1 || true
    fi
    
    # Try different download methods for better speed
    if [ "$SKIP_DOWNLOAD" = false ]; then
        DOWNLOAD_SUCCESS=false
    fi
    
    if [ "$SKIP_DOWNLOAD" = false ] && command -v aria2c >/dev/null 2>&1; then
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
    
    # Verify download completed (only if we were supposed to download)
    if [ "$SKIP_DOWNLOAD" = false ] && [ ! -f "$LATEST" ]; then
        print_error "Download failed - file not found after download attempts"
        exit 1
    fi
    
    # Check if extraction was already done or partially done
    EXTRACTION_NEEDED=true
    if [ -d "$HOME/backup" ]; then
        print_status "Found 'backup' directory from previous extraction attempt..."
        BACKUP_SIZE=$(du -sm "$HOME/backup" 2>/dev/null | cut -f1)
        if [ "$BACKUP_SIZE" -gt 20000 ]; then  # If > 20GB, probably complete
            print_success "Extraction appears complete (${BACKUP_SIZE}MB), skipping..."
            EXTRACTION_NEEDED=false
        else
            print_warning "Partial extraction found (${BACKUP_SIZE}MB), will resume..."
            # Keep the partial extraction, tar will skip existing files
        fi
    elif [ -d "$HOME/${LATEST%.*.*}" ]; then
        print_status "Found extracted directory from previous attempt..."
        EXTRACTION_NEEDED=false
    elif [ -d "$HOME/chain" ] && [ -d "$HOME/block_store" ]; then
        print_status "Found extracted blockchain directories in home folder..."
        EXTRACTION_NEEDED=false
    elif [ -d "$HOME/.koinos/chain" ] && [ -d "$HOME/.koinos/block_store" ]; then
        print_success "Blockchain data already in place at ~/.koinos, skipping extraction..."
        EXTRACTION_NEEDED=false
    fi
    
    if [ "$EXTRACTION_NEEDED" = true ] && [ -f "$LATEST" ]; then
        print_status "Extracting snapshot (this will use additional ~30GB temporarily)..."
        
        # Get total size for progress tracking
        ARCHIVE_SIZE=$(stat -c%s "$LATEST" 2>/dev/null || stat -f%z "$LATEST" 2>/dev/null)
        
        # Install tools for faster extraction
        if ! command -v pv >/dev/null 2>&1; then
            print_status "Installing 'pv' for extraction progress monitoring..."
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y pv >/dev/null 2>&1
        fi
        
        # Install pigz for parallel extraction (MUCH faster)
        if ! command -v pigz >/dev/null 2>&1; then
            print_status "Installing 'pigz' for parallel extraction (uses all CPU cores)..."
            sudo apt-get install -y pigz >/dev/null 2>&1
        fi
        
        # Create extraction wrapper for resume support
        extract_with_resume() {
            local MAX_RETRIES=3
            local RETRY_COUNT=0
            
            while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                print_status "Extraction attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES..."
                
                # Determine number of CPU cores for parallel extraction
                CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
                
                # Use pigz for MUCH faster parallel extraction if available
                if command -v pigz >/dev/null 2>&1 && command -v pv >/dev/null 2>&1; then
                    print_status "Using parallel extraction with $CPU_CORES CPU cores..."
                    print_success "This should be ${CPU_CORES}x faster than standard extraction!"
                    
                    # Parallel extraction with progress bar
                    if pv -petrab $LATEST | pigz -dc -p $CPU_CORES | tar -xf - --skip-old-files 2>/dev/null || \
                       pv -petrab $LATEST | pigz -dc -p $CPU_CORES | tar -xf -; then
                        return 0  # Success
                    else
                        print_warning "Parallel extraction interrupted or failed, will retry..."
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                        sleep 5
                    fi
                elif command -v pigz >/dev/null 2>&1; then
                    print_status "Using parallel extraction with $CPU_CORES CPU cores (no progress bar)..."
                    
                    # Parallel extraction without progress bar
                    if pigz -dc -p $CPU_CORES $LATEST | tar -xf - --skip-old-files 2>/dev/null || \
                       pigz -dc -p $CPU_CORES $LATEST | tar -xf -; then
                        return 0  # Success
                    else
                        print_warning "Parallel extraction interrupted or failed, will retry..."
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                        sleep 5
                    fi
                elif command -v pv >/dev/null 2>&1; then
                    print_status "Extracting with progress indicator (single-threaded, install 'pigz' for ${CPU_CORES}x speedup)..."
                    # Fallback to standard extraction with progress
                    if pv -petrab $LATEST | tar -xzf - --skip-old-files 2>/dev/null || \
                       pv -petrab $LATEST | tar -xzkf - 2>/dev/null || \
                       pv -petrab $LATEST | tar -xzf -; then
                        return 0  # Success
                    else
                        print_warning "Extraction interrupted or failed, will retry..."
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                        sleep 5
                    fi
                else
                    print_status "Extracting (install 'pigz' and 'pv' for ${CPU_CORES}x faster extraction with progress)..."
                    # Fallback to basic tar
                    if tar -xzf $LATEST --skip-old-files 2>/dev/null || \
                       tar -xzkf $LATEST 2>/dev/null || \
                       tar -xzf $LATEST; then
                        return 0  # Success
                    else
                        print_warning "Extraction interrupted or failed, will retry..."
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                        sleep 5
                    fi
                fi
                
                # Check if we made progress
                if [ -d "$HOME/backup" ]; then
                    NEW_SIZE=$(du -sm "$HOME/backup" 2>/dev/null | cut -f1)
                    print_status "Extracted ${NEW_SIZE}MB so far..."
                fi
            done
            
            return 1  # Failed after all retries
        }
        
        # Run extraction with resume support
        if extract_with_resume; then
            print_success "Extraction completed successfully!"
            
            # Only delete archive after successful extraction
            print_status "Cleaning up archive to free ~30GB..."
            rm -f $LATEST
            rm -f "${LATEST}.backup" 2>/dev/null  # Clean up any backup file
        else
            print_error "Failed to extract snapshot after multiple attempts"
            print_status "Archive preserved at: $LATEST"
            print_status "You can retry by running the script again"
            exit 1
        fi
    elif [ "$EXTRACTION_NEEDED" = false ]; then
        print_status "Skipping extraction, already completed"
        # Clean up archive if extraction is already done
        if [ -f "$LATEST" ]; then
            print_status "Removing archive file to free space..."
            rm -f $LATEST
            rm -f "${LATEST}.backup" 2>/dev/null
        fi
    else
        print_warning "No archive file found to extract"
    fi
    
    # Move to correct location - check various possible extraction patterns
    # This should run whether we downloaded or found existing directories
    if [ -d "backup" ]; then
        print_status "Moving 'backup' directory to ~/.koinos..."
        rm -rf ~/.koinos 2>/dev/null  # Remove any incomplete data
        mv backup ~/.koinos
        print_success "Blockchain data moved to ~/.koinos"
    elif [ -d "${LATEST%.*.*}" ]; then
        print_status "Moving '${LATEST%.*.*}' directory to ~/.koinos..."
        mv "${LATEST%.*.*}" ~/.koinos
    elif [ -d "chain" ] && [ -d "block_store" ]; then
        # Files were extracted directly to current directory
        print_status "Snapshot extracted directly to current directory, organizing..."
        mkdir -p ~/.koinos
        
        # Move all blockchain directories to ~/.koinos
        for dir in chain block_store account_history contract_meta_store transaction_store mempool p2p grpc jsonrpc; do
            if [ -d "$dir" ]; then
                print_status "Moving $dir to ~/.koinos/"
                mv "$dir" ~/.koinos/ 2>/dev/null || true
            fi
        done
        
        # Move config file if exists
        if [ -f "config.yml" ]; then
            mv config.yml ~/.koinos/ 2>/dev/null || true
        fi
    else
        # Try to detect any blockchain data directories
        if ls -d */ 2>/dev/null | grep -qE "(chain|block_store|account_history)"; then
            print_status "Found blockchain directories, moving to ~/.koinos..."
            mkdir -p ~/.koinos
            
            # Move any recognized blockchain directories
            for dir in */; do
                case "$dir" in
                    chain/|block_store/|account_history/|contract_meta_store/|transaction_store/|mempool/|p2p/|grpc/|jsonrpc/)
                        print_status "Moving $dir to ~/.koinos/"
                        mv "$dir" ~/.koinos/ 2>/dev/null || true
                        ;;
                esac
            done
        else
            print_error "Could not find extracted snapshot directory structure"
            print_status "Current directory contents:"
            ls -la
            print_status "Expected to find directories like: chain, block_store, account_history"
            exit 1
        fi
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
    
    # Start with new group membership (Docker group) if sg is available
    if command -v sg >/dev/null 2>&1; then
        sg docker -c "docker compose --profile all up -d"
    else
        # Fallback for systems without sg command (macOS, some Linux distros)
        print_status "Starting without sg command..."
        docker compose --profile all up -d || {
            print_warning "May need to logout/login for Docker group changes to take effect"
            docker compose --profile all up -d
        }
    fi
    
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
    # Get external IP once with fallback
    EXTERNAL_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo "API Endpoints:"
    echo "• JSON-RPC: http://${EXTERNAL_IP}:8080"
    echo "• CORS Proxy (for browsers): http://${EXTERNAL_IP}:8081"
    echo "• gRPC: http://${EXTERNAL_IP}:50051"
    echo "• P2P: port 8888"
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