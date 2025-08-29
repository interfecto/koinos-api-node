#!/bin/bash

# Koinos Node Status Script
# Provides comprehensive status information about your Koinos node

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}===================================${NC}"
}

print_section() {
    echo -e "${PURPLE}=== $1 ===${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if jq is available
check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        print_warning "jq not found. Installing for better JSON parsing..."
        sudo apt-get update && sudo apt-get install -y jq >/dev/null 2>&1
    fi
}

# Function to get API response
get_api_response() {
    local endpoint="$1"
    local method="$2"
    local params="$3"
    
    curl -s -X POST -H "Content-Type: application/json" \
         -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
         "$endpoint" 2>/dev/null
}

# Function to extract result from JSON response
extract_result() {
    local response="$1"
    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.result // empty'
    else
        # Fallback without jq
        echo "$response" | sed -n 's/.*"result":\([^}]*\).*/\1/p'
    fi
}

# Main status function
main() {
    clear
    print_header "Koinos Node Status - $(date)"
    echo
    
    # Check if in koinos directory
    if [ ! -f ~/koinos/docker-compose.yml ]; then
        print_error "Koinos installation not found at ~/koinos/"
        exit 1
    fi
    
    cd ~/koinos
    
    # Container Status
    print_section "Container Status"
    if command -v docker >/dev/null 2>&1; then
        if docker compose ps >/dev/null 2>&1; then
            docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}" | while read line; do
                if echo "$line" | grep -q "Up"; then
                    print_success "$line"
                elif echo "$line" | grep -q "Exit"; then
                    print_error "$line"
                else
                    echo "$line"  # Header line
                fi
            done
        else
            print_error "Docker Compose not responding"
        fi
    else
        print_error "Docker not found"
    fi
    echo
    
    # API Health Check
    print_section "API Health Check"
    
    # Check CORS proxy (port 8081)
    CORS_RESPONSE=$(get_api_response "http://localhost:8081" "chain.get_head_info" "{}")
    if [ -n "$CORS_RESPONSE" ] && echo "$CORS_RESPONSE" | grep -q "result"; then
        print_success "CORS Proxy (8081): Responding"
    else
        print_error "CORS Proxy (8081): Not responding"
    fi
    
    # Check JSON-RPC (port 8080)
    JSONRPC_RESPONSE=$(get_api_response "http://localhost:8080" "chain.get_head_info" "{}")
    if [ -n "$JSONRPC_RESPONSE" ] && echo "$JSONRPC_RESPONSE" | grep -q "result"; then
        print_success "JSON-RPC (8080): Responding"
    else
        print_error "JSON-RPC (8080): Not responding"
    fi
    
    # Check health endpoint
    HEALTH_CHECK=$(curl -s http://localhost:8081/health 2>/dev/null)
    if [ "$HEALTH_CHECK" = "OK" ]; then
        print_success "Health Endpoint: OK"
    else
        print_warning "Health Endpoint: No response"
    fi
    echo
    
    # Blockchain Status
    print_section "Blockchain Status"
    
    check_jq
    
    # Get current height and info
    if [ -n "$JSONRPC_RESPONSE" ] && echo "$JSONRPC_RESPONSE" | grep -q "result"; then
        if command -v jq >/dev/null 2>&1; then
            HEIGHT=$(echo "$JSONRPC_RESPONSE" | jq -r '.result.head_topology.height // "unknown"')
            BLOCK_ID=$(echo "$JSONRPC_RESPONSE" | jq -r '.result.head_topology.id // "unknown"')
            BLOCK_TIME=$(echo "$JSONRPC_RESPONSE" | jq -r '.result.head_block_time // "unknown"')
            LIB=$(echo "$JSONRPC_RESPONSE" | jq -r '.result.last_irreversible_block // "unknown"')
        else
            HEIGHT=$(echo "$JSONRPC_RESPONSE" | grep -o '"height":"[^"]*"' | cut -d'"' -f4)
            BLOCK_TIME=$(echo "$JSONRPC_RESPONSE" | grep -o '"head_block_time":"[^"]*"' | cut -d'"' -f4)
        fi
        
        if [ "$HEIGHT" != "unknown" ] && [ -n "$HEIGHT" ]; then
            print_status "Current Block Height: $(echo $HEIGHT | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')"
            
            if [ "$BLOCK_TIME" != "unknown" ] && [ -n "$BLOCK_TIME" ]; then
                # Convert milliseconds to seconds and format date
                BLOCK_TIME_SEC=$((BLOCK_TIME / 1000))
                FORMATTED_TIME=$(date -d "@$BLOCK_TIME_SEC" 2>/dev/null || echo "Invalid time")
                print_status "Last Block Time: $FORMATTED_TIME"
                
                # Check if node is synced (within 5 minutes of current time)
                CURRENT_TIME=$(date +%s)
                TIME_DIFF=$((CURRENT_TIME - BLOCK_TIME_SEC))
                
                if [ "$TIME_DIFF" -lt 300 ]; then
                    print_success "Sync Status: SYNCED (${TIME_DIFF}s behind)"
                elif [ "$TIME_DIFF" -lt 3600 ]; then
                    print_warning "Sync Status: SYNCING ($((TIME_DIFF / 60))m behind)"
                else
                    print_error "Sync Status: OUT OF SYNC ($((TIME_DIFF / 3600))h behind)"
                fi
            fi
            
            if [ "$LIB" != "unknown" ] && [ -n "$LIB" ]; then
                print_status "Last Irreversible Block: $(echo $LIB | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')"
            fi
        else
            print_warning "Could not retrieve block height"
        fi
    else
        print_error "API not responding - node may be starting up"
    fi
    echo
    
    # Sync Progress (from logs)
    print_section "Recent Sync Activity"
    if docker compose logs --tail=5 chain 2>/dev/null | grep -E "(Sync progress|Height:|Finished indexing)" | tail -3 | while read line; do
        if echo "$line" | grep -q "Sync progress"; then
            HEIGHT_LOG=$(echo "$line" | grep -o 'Height: [0-9]*' | cut -d' ' -f2)
            TIME_REMAINING=$(echo "$line" | grep -o '([^)]*block time remaining)' | sed 's/[()]//g')
            print_status "Syncing to height $(echo $HEIGHT_LOG | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta') - $TIME_REMAINING"
        elif echo "$line" | grep -q "Finished indexing"; then
            print_success "$line"
        else
            print_status "$line"
        fi
    done; then
        true
    else
        print_warning "No recent sync activity found in logs"
    fi
    echo
    
    # System Resources
    print_section "System Resources"
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        MEMORY_INFO=$(free -h | awk 'NR==2{printf "Used: %s/%s (%.1f%%)", $3,$2,$3*100/$2}')
        print_status "Memory: $MEMORY_INFO"
    fi
    
    # Disk usage
    if command -v df >/dev/null 2>&1; then
        DISK_INFO=$(df -h / | awk 'NR==2{printf "Used: %s/%s (%s)", $3,$2,$5}')
        print_status "Disk: $DISK_INFO"
        
        # Check if disk usage is high
        DISK_PERCENT=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
        if [ "$DISK_PERCENT" -gt 90 ]; then
            print_error "Disk usage is critically high (${DISK_PERCENT}%)"
        elif [ "$DISK_PERCENT" -gt 80 ]; then
            print_warning "Disk usage is high (${DISK_PERCENT}%)"
        fi
    fi
    
    # Load average
    if [ -f /proc/loadavg ]; then
        LOAD_AVG=$(cat /proc/loadavg | cut -d' ' -f1-3)
        print_status "Load Average: $LOAD_AVG"
    fi
    
    # Docker resource usage
    if command -v docker >/dev/null 2>&1; then
        echo
        print_status "Docker Container Resources:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep koinos | head -5
    fi
    echo
    
    # Network Status
    print_section "Network Status"
    
    # Check listening ports
    if command -v ss >/dev/null 2>&1; then
        print_status "Listening Ports:"
        ss -tlnp | grep -E ":808[01]|:3000|:50051|:8888" | while read line; do
            PORT=$(echo "$line" | awk '{print $4}' | cut -d':' -f2)
            case $PORT in
                8080) print_success "  JSON-RPC: $line" ;;
                8081) print_success "  CORS Proxy: $line" ;;
                3000) print_success "  REST API: $line" ;;
                50051) print_success "  gRPC: $line" ;;
                8888) print_success "  P2P: $line" ;;
                *) print_status "  Other: $line" ;;
            esac
        done
    elif command -v netstat >/dev/null 2>&1; then
        print_status "Listening Ports:"
        netstat -tlnp | grep -E ":808[01]|:3000|:50051|:8888" | while read line; do
            print_success "  $line"
        done
    fi
    echo
    
    # Recent Errors
    print_section "Recent Errors (Last 24 Hours)"
    ERROR_COUNT=$(docker compose logs --since=24h 2>/dev/null | grep -i error | wc -l)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        print_warning "Found $ERROR_COUNT error(s) in logs"
        docker compose logs --since=24h 2>/dev/null | grep -i error | tail -3 | while read line; do
            print_error "  $line"
        done
    else
        print_success "No errors found in recent logs"
    fi
    echo
    
    # Quick Commands
    print_section "Quick Commands"
    echo "View live logs:     docker compose -f ~/koinos/docker-compose.yml logs -f chain"
    echo "Restart node:       ~/koinos-manage.sh restart"
    echo "Stop node:          ~/koinos-manage.sh stop"
    echo "Start node:         ~/koinos-manage.sh start"
    echo "Update node:        ~/koinos-manage.sh update"
    if [ -f ~/backup-koinos-data.sh ]; then
        echo "Create backup:      ~/backup-koinos-data.sh"
    fi
    echo
    
    print_header "Status Check Complete"
}

# Run main function
main "$@"