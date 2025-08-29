#!/bin/bash

# Koinos Node Management Script
# Provides easy management of your Koinos node services

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if we're in the right directory
check_koinos_installation() {
    if [ ! -f ~/koinos/docker-compose.yml ]; then
        print_error "Koinos installation not found at ~/koinos/"
        print_error "Please ensure the Koinos node installer has been run successfully."
        exit 1
    fi
}

# Function to check if services are running
check_services_status() {
    cd ~/koinos
    local running_count=$(docker compose ps | grep "Up" | wc -l)
    local total_count=$(docker compose ps | grep -v "NAME" | wc -l)
    
    if [ "$running_count" -eq "$total_count" ] && [ "$total_count" -gt 0 ]; then
        return 0  # All services running
    else
        return 1  # Some or no services running
    fi
}

# Start the node
start_node() {
    print_status "Starting Koinos node..."
    cd ~/koinos
    
    if docker compose --profile all up -d; then
        print_success "Koinos node started successfully"
        
        # Wait a moment for services to initialize
        sleep 5
        
        # Check if services are running
        if check_services_status; then
            print_success "All services are running"
            
            # Show quick status
            echo
            print_status "Service Status:"
            docker compose ps --format "table {{.Service}}\t{{.Status}}"
            
            echo
            print_status "API endpoints will be available at:"
            echo "  • CORS Proxy: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):8081"
            echo "  • JSON-RPC: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):8080"
            echo "  • gRPC: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):50051"
            echo "  • REST: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):3000"
            
            echo
            print_status "Monitor sync progress with: docker compose logs -f chain"
        else
            print_warning "Some services may not have started properly"
            print_status "Check status with: docker compose ps"
        fi
    else
        print_error "Failed to start Koinos node"
        print_status "Check logs with: docker compose logs"
        exit 1
    fi
}

# Stop the node
stop_node() {
    print_status "Stopping Koinos node..."
    cd ~/koinos
    
    if docker compose --profile all down; then
        print_success "Koinos node stopped successfully"
        
        # Verify all containers are stopped
        local running=$(docker compose ps --format "{{.Service}}" | wc -l)
        if [ "$running" -eq 0 ]; then
            print_success "All services stopped"
        else
            print_warning "Some services may still be running"
            docker compose ps
        fi
    else
        print_error "Failed to stop Koinos node"
        exit 1
    fi
}

# Restart the node
restart_node() {
    print_status "Restarting Koinos node..."
    cd ~/koinos
    
    if docker compose --profile all restart; then
        print_success "Koinos node restarted successfully"
        
        # Wait for services to come up
        sleep 5
        
        if check_services_status; then
            print_success "All services are running after restart"
        else
            print_warning "Some services may not be running properly after restart"
        fi
    else
        print_error "Failed to restart Koinos node"
        exit 1
    fi
}

# Show logs
show_logs() {
    local service="${2:-chain}"  # Default to chain service
    
    print_status "Showing logs for service: $service"
    print_status "Press Ctrl+C to stop following logs"
    cd ~/koinos
    
    if [ "$service" = "all" ]; then
        docker compose logs -f
    else
        docker compose logs -f "$service"
    fi
}

# Update node
update_node() {
    print_status "Updating Koinos node..."
    cd ~/koinos
    
    # Check current status
    local was_running=false
    if check_services_status; then
        was_running=true
        print_status "Node is currently running, will restart after update"
    fi
    
    # Pull latest images
    print_status "Pulling latest Docker images..."
    if docker compose pull; then
        print_success "Docker images updated"
    else
        print_error "Failed to pull latest images"
        exit 1
    fi
    
    # Restart services if they were running
    if [ "$was_running" = true ]; then
        print_status "Restarting services with updated images..."
        docker compose --profile all down
        docker compose --profile all up -d
        
        # Wait and check status
        sleep 10
        if check_services_status; then
            print_success "Node updated and restarted successfully"
        else
            print_warning "Node updated but some services may not be running"
        fi
    else
        print_success "Node images updated. Start the node to use new versions."
    fi
    
    # Clean up old images
    print_status "Cleaning up old Docker images..."
    docker image prune -f >/dev/null 2>&1
    print_success "Cleanup completed"
}

# Show node status
show_status() {
    if [ -f ~/koinos-status.sh ]; then
        ~/koinos-status.sh
    else
        print_status "Basic status check..."
        cd ~/koinos
        
        echo "Service Status:"
        docker compose ps
        
        echo
        echo "Recent Chain Logs:"
        docker compose logs --tail=5 chain
    fi
}

# Backup node data
backup_data() {
    if [ -f ~/backup-koinos-data.sh ]; then
        print_status "Starting backup process..."
        ~/backup-koinos-data.sh
    else
        print_error "Backup script not found at ~/backup-koinos-data.sh"
        print_status "You can create backups manually with:"
        echo "  tar -czf koinos-backup-\$(date +%Y%m%d).tar.gz ~/.koinos/"
    fi
}

# Reset node (dangerous operation)
reset_node() {
    print_warning "This will completely reset your node and download fresh blockchain data!"
    print_warning "This operation cannot be undone!"
    echo
    read -p "Are you absolutely sure? Type 'yes' to continue: " -r
    
    if [ "$REPLY" = "yes" ]; then
        print_status "Stopping node..."
        cd ~/koinos
        docker compose --profile all down
        
        print_status "Backing up current data..."
        if [ -d ~/.koinos ]; then
            mv ~/.koinos ~/.koinos_backup_$(date +%Y%m%d_%H%M%S)
            print_success "Current data backed up"
        fi
        
        print_status "Downloading fresh snapshot..."
        cd ~
        LATEST=$(curl -s https://backup.koinosblocks.com/ | grep -oP 'backup_\d{4}-\d{2}-\d{2}\.tar\.gz' | sort | tail -n 1)
        if [ -n "$LATEST" ]; then
            print_status "Downloading: $LATEST"
            wget --progress=bar:force https://backup.koinosblocks.com/$LATEST -O $LATEST
            tar -xzf $LATEST
            
            if [ -d "backup" ]; then
                mv backup ~/.koinos
            else
                print_error "Could not find extracted backup directory"
                exit 1
            fi
            
            rm $LATEST
            print_success "Fresh blockchain data installed"
            
            print_status "Starting node with fresh data..."
            cd ~/koinos
            docker compose --profile all up -d
            print_success "Node reset complete!"
        else
            print_error "Could not find latest snapshot"
            exit 1
        fi
    else
        print_status "Reset cancelled"
    fi
}

# Show usage information
show_usage() {
    echo "Koinos Node Management Script"
    echo
    echo "Usage: $0 {command} [options]"
    echo
    echo "Commands:"
    echo "  start          Start the Koinos node"
    echo "  stop           Stop the Koinos node" 
    echo "  restart        Restart the Koinos node"
    echo "  status         Show detailed node status"
    echo "  logs [service] Show logs (default: chain service)"
    echo "  update         Update node to latest version"
    echo "  backup         Create backup of blockchain data"
    echo "  reset          Reset node with fresh data (DANGEROUS)"
    echo
    echo "Log Services:"
    echo "  chain          Blockchain service logs (default)"
    echo "  jsonrpc        JSON-RPC API logs"
    echo "  cors-proxy     CORS proxy logs"
    echo "  p2p            P2P network logs"
    echo "  all            All service logs"
    echo
    echo "Examples:"
    echo "  $0 start                 # Start the node"
    echo "  $0 logs                  # Show chain logs"
    echo "  $0 logs jsonrpc          # Show JSON-RPC logs"
    echo "  $0 logs all              # Show all logs"
    echo
}

# Main script logic
main() {
    case "$1" in
        start)
            check_koinos_installation
            start_node
            ;;
        stop)
            check_koinos_installation
            stop_node
            ;;
        restart)
            check_koinos_installation
            restart_node
            ;;
        status)
            check_koinos_installation
            show_status
            ;;
        logs)
            check_koinos_installation
            show_logs "$@"
            ;;
        update)
            check_koinos_installation
            update_node
            ;;
        backup)
            check_koinos_installation
            backup_data
            ;;
        reset)
            check_koinos_installation
            reset_node
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function with all arguments
main "$@"