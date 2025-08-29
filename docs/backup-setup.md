# Backup Setup Guide

This guide covers setting up automated backups for your Koinos node data.

## Backup Strategy

There are two main approaches to backing up your Koinos node:

1. **Full System Backup**: Complete droplet/server backup
2. **Data-Only Backup**: Just the blockchain data directory

## Data-Only Backup (Recommended)

Data-only backups are smaller, faster, and contain just the essential blockchain data.

### Creating the Backup Script

Create the backup script:
```bash
nano ~/backup-koinos-data.sh
chmod +x ~/backup-koinos-data.sh
```

Add this content:
```bash
#!/bin/bash

# Koinos Data Backup Script
# Creates compressed backup of blockchain data

DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$HOME/koinos-backups"
BACKUP_FILE="koinos-data-$DATE.tar.gz"
TEMP_DIR="/tmp/koinos-backup-$DATE"

# Configuration
KEEP_DAYS=30  # Keep backups for 30 days
MAX_BACKUPS=10  # Keep maximum 10 backups

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Create backup directory
mkdir -p "$BACKUP_DIR"

print_status "Starting Koinos data backup..."
print_status "Backup file: $BACKUP_FILE"

# Check available disk space
REQUIRED_SPACE=$(du -sm ~/.koinos | cut -f1)
AVAILABLE_SPACE=$(df "$BACKUP_DIR" | awk 'NR==2 {print int($4/1024)}')

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    print_error "Insufficient disk space. Required: ${REQUIRED_SPACE}MB, Available: ${AVAILABLE_SPACE}MB"
    exit 1
fi

# Check if node is running
NODE_RUNNING=false
if docker compose -f ~/koinos/docker-compose.yml ps | grep -q "Up"; then
    NODE_RUNNING=true
    print_status "Node is running. Creating hot backup (may have slight inconsistencies)"
else
    print_status "Node is stopped. Creating consistent backup"
fi

# Create the backup
print_status "Compressing blockchain data..."
cd ~ && tar -czf "$BACKUP_DIR/$BACKUP_FILE" .koinos/ 2>/dev/null

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    print_success "Backup created successfully: $BACKUP_SIZE"
else
    print_error "Backup creation failed"
    exit 1
fi

# Cleanup old backups by date
print_status "Cleaning up old backups (older than $KEEP_DAYS days)..."
find "$BACKUP_DIR" -name "koinos-data-*.tar.gz" -mtime +$KEEP_DAYS -delete

# Cleanup old backups by count
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/koinos-data-*.tar.gz 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    print_status "Removing excess backups (keeping $MAX_BACKUPS newest)..."
    ls -t "$BACKUP_DIR"/koinos-data-*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
fi

# Show backup statistics
print_status "Backup Statistics:"
echo "  Location: $BACKUP_DIR"
echo "  File: $BACKUP_FILE"
echo "  Size: $BACKUP_SIZE"
echo "  Backups in directory: $(ls -1 "$BACKUP_DIR"/koinos-data-*.tar.gz 2>/dev/null | wc -l)"

print_success "Backup process completed!"
```

### Test the Backup Script

```bash
# Run the backup manually to test
~/backup-koinos-data.sh

# Check that backup was created
ls -la ~/koinos-backups/
```

### Schedule Automated Backups

Set up automatic backups using cron:

```bash
# Edit crontab
crontab -e

# Add one of these lines:

# Daily backup at 2 AM
0 2 * * * /home/$(whoami)/backup-koinos-data.sh >> /home/$(whoami)/backup.log 2>&1

# Weekly backup every Sunday at 2 AM  
0 2 * * 0 /home/$(whoami)/backup-koinos-data.sh >> /home/$(whoami)/backup.log 2>&1

# Bi-weekly backup (every other Sunday)
0 2 * * 0 [ $(date +\%W) -eq $(($(date +\%W) \% 2)) ] && /home/$(whoami)/backup-koinos-data.sh >> /home/$(whoami)/backup.log 2>&1
```

## Cloud Storage Integration

### DigitalOcean Spaces

Upload backups to DigitalOcean Spaces:

```bash
# Install s3cmd
sudo apt-get install s3cmd

# Configure s3cmd for DigitalOcean Spaces
s3cmd --configure
# Enter your Spaces access key, secret key
# Host: nyc3.digitaloceanspaces.com (or your region)
# Bucket: your-bucket-name
```

Add to backup script:
```bash
# After backup creation, add:
print_status "Uploading to DigitalOcean Spaces..."
s3cmd put "$BACKUP_DIR/$BACKUP_FILE" s3://your-bucket/koinos-backups/

if [ $? -eq 0 ]; then
    print_success "Backup uploaded to cloud storage"
    # Optional: Remove local backup after successful upload
    # rm "$BACKUP_DIR/$BACKUP_FILE"
else
    print_warning "Cloud upload failed, backup remains local"
fi
```

### AWS S3

For AWS S3 integration:

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure
```

Add to backup script:
```bash
# Upload to S3
print_status "Uploading to AWS S3..."
aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" s3://your-bucket/koinos-backups/
```

### Google Cloud Storage

```bash
# Install Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

Add to backup script:
```bash
# Upload to Google Cloud Storage
print_status "Uploading to Google Cloud Storage..."
gsutil cp "$BACKUP_DIR/$BACKUP_FILE" gs://your-bucket/koinos-backups/
```

## Backup Restoration

### Restoring from Local Backup

Create a restoration script:

```bash
nano ~/restore-koinos-data.sh
chmod +x ~/restore-koinos-data.sh
```

```bash
#!/bin/bash

# Koinos Data Restoration Script

BACKUP_DIR="$HOME/koinos-backups"

print_status() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# List available backups
echo "Available backups:"
ls -la "$BACKUP_DIR"/koinos-data-*.tar.gz 2>/dev/null

if [ $? -ne 0 ]; then
    print_error "No backups found in $BACKUP_DIR"
    exit 1
fi

# Get backup file from user or use latest
if [ -z "$1" ]; then
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/koinos-data-*.tar.gz | head -1)
    print_status "Using latest backup: $(basename $BACKUP_FILE)"
else
    BACKUP_FILE="$BACKUP_DIR/$1"
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
fi

# Confirm restoration
echo
print_status "This will replace your current blockchain data!"
print_status "Backup file: $BACKUP_FILE"
read -p "Continue? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Restoration cancelled"
    exit 0
fi

# Stop the node
print_status "Stopping Koinos node..."
cd ~/koinos && docker compose --profile all down

# Backup current data
if [ -d ~/.koinos ]; then
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    print_status "Backing up current data to ~/.koinos_backup_$BACKUP_TIMESTAMP"
    mv ~/.koinos ~/.koinos_backup_$BACKUP_TIMESTAMP
fi

# Restore from backup
print_status "Restoring blockchain data..."
cd ~ && tar -xzf "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    print_success "Data restored successfully"
else
    print_error "Restoration failed"
    exit 1
fi

# Start the node
print_status "Starting Koinos node..."
cd ~/koinos && docker compose --profile all up -d

print_success "Restoration completed!"
print_status "Monitor startup: docker compose -f ~/koinos/docker-compose.yml logs -f chain"
```

### Usage

```bash
# Restore from latest backup
~/restore-koinos-data.sh

# Restore from specific backup
~/restore-koinos-data.sh koinos-data-2024-08-28_02-00-01.tar.gz
```

## Monitoring Backups

### Backup Status Script

```bash
nano ~/backup-status.sh
chmod +x ~/backup-status.sh
```

```bash
#!/bin/bash

BACKUP_DIR="$HOME/koinos-backups"

echo "=== Koinos Backup Status ==="
echo "Backup directory: $BACKUP_DIR"
echo

if [ ! -d "$BACKUP_DIR" ]; then
    echo "No backup directory found"
    exit 1
fi

BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/koinos-data-*.tar.gz 2>/dev/null | wc -l)
echo "Total backups: $BACKUP_COUNT"

if [ "$BACKUP_COUNT" -gt 0 ]; then
    echo
    echo "Recent backups:"
    ls -lth "$BACKUP_DIR"/koinos-data-*.tar.gz | head -5
    
    echo
    LATEST=$(ls -t "$BACKUP_DIR"/koinos-data-*.tar.gz | head -1)
    LATEST_SIZE=$(du -h "$LATEST" | cut -f1)
    LATEST_DATE=$(stat -c %y "$LATEST" | cut -d' ' -f1)
    echo "Latest backup: $(basename $LATEST) ($LATEST_SIZE, $LATEST_DATE)"
    
    echo
    TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    echo "Total backup size: $TOTAL_SIZE"
fi

# Check last backup log
if [ -f ~/backup.log ]; then
    echo
    echo "Last backup log entries:"
    tail -10 ~/backup.log
fi
```

### Backup Health Check

Add to your monitoring:

```bash
# Add to ~/koinos-status.sh
echo
echo "=== Backup Status ==="
~/backup-status.sh
```

## Advanced Backup Options

### Incremental Backups

For very large nodes, consider incremental backups:

```bash
#!/bin/bash

# Incremental backup using rsync
BACKUP_BASE="$HOME/koinos-backups/base"
BACKUP_INCR="$HOME/koinos-backups/incremental"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Create base backup if it doesn't exist
if [ ! -d "$BACKUP_BASE" ]; then
    mkdir -p "$BACKUP_BASE"
    rsync -av ~/.koinos/ "$BACKUP_BASE/"
    echo "Base backup created"
else
    # Create incremental backup
    mkdir -p "$BACKUP_INCR/$DATE"
    rsync -av --link-dest="$BACKUP_BASE" ~/.koinos/ "$BACKUP_INCR/$DATE/"
    echo "Incremental backup created: $DATE"
fi
```

### Database-Specific Backups

For database-level backups (if Koinos supports it):

```bash
#!/bin/bash

# Stop services
docker compose -f ~/koinos/docker-compose.yml stop

# Backup specific databases
tar -czf "chain-db-backup-$(date +%Y%m%d).tar.gz" ~/.koinos/chain/
tar -czf "account-history-backup-$(date +%Y%m%d).tar.gz" ~/.koinos/account_history/

# Restart services
docker compose -f ~/koinos/docker-compose.yml start
```

## Backup Best Practices

1. **Test Restores**: Regularly test backup restoration on a separate system
2. **Multiple Locations**: Store backups in multiple locations (local + cloud)
3. **Encryption**: Encrypt sensitive backups before cloud upload
4. **Monitoring**: Set up alerts for backup failures
5. **Documentation**: Document your backup and restore procedures
6. **Rotation**: Implement proper backup rotation to manage storage costs

## Troubleshooting Backups

### Common Issues

**Backup script fails with permission errors:**
```bash
# Ensure script is executable
chmod +x ~/backup-koinos-data.sh

# Check disk permissions
ls -la ~/koinos-backups/
```

**Insufficient disk space:**
```bash
# Check space usage
df -h
du -sh ~/.koinos

# Clean up old backups
find ~/koinos-backups -name "koinos-data-*.tar.gz" -mtime +7 -delete
```

**Cloud upload failures:**
```bash
# Test cloud credentials
s3cmd ls  # For DigitalOcean Spaces
aws s3 ls  # For AWS S3

# Check network connectivity
curl -I https://nyc3.digitaloceanspaces.com
```

This backup system ensures your Koinos node data is protected and can be quickly restored when needed.