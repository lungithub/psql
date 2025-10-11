#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# PostgreSQL User Migration Script v2025.4
# Migrates postgres user from UID 1005 to system range (100-999)
#
# Prerequisites:
# 1. Stop PostgreSQL: 
#       sudo systemctl stop postgresql@13-main.service --no-pager
# 2. Find available system UID: 
#       sudo getent passwd | awk -F: '$3 >= 100 && $3 <= 999 {print $3}' | sort -n
#
# These locations are owned by root
# /usr/share/postgresql/ <--- contains sample configs, owned by root
# /var/cache/postgresql/ <--- contains cached data, owned by root
# /etc/default/ <--- contains environment settings, nothing for postgres by default
# /var/log/syslog or /var/log/messages <--- contains log output, all owned by root
#
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

USERNAME="postgres"
NEW_USERID=154
NEW_GROUPID=154
OLD_USERID=153
OLD_GROUPID=153

DB_DIR=/db # database files custom location
CONFIG_DIR=/etc/postgresql # config files
LOG_DIR=/var/log/postgresql # log files
HOME_DIR=/var/lib/postgresql # default DB location
VAR_RUN=/var/run/postgresql # runtime files
USR_LIB=/usr/lib/postgresql # library files

function checkvars(){
    echo
    echo "Running: $FUNCNAME"  
    echo "-----"
    echo "New User id ...: ${NEW_USERID}"
    echo "New Group id ..: ${NEW_GROUPID}"
    echo "Username ......: ${USERNAME}"
    echo "Old User id ...: ${OLD_USERID}"
    echo "Old Group id ..: ${OLD_GROUPID}"
    echo "-----"
    echo "DB Directory ...: ${DB_DIR}"
    echo "Config Directory: ${CONFIG_DIR}"
    echo "Log Directory ..: ${LOG_DIR}"
    echo "Home Directory .: ${HOME_DIR}"
    echo "Var Run Dir ....: ${VAR_RUN}"
    echo "Usr Lib Dir ....: ${USR_LIB}"
    echo "-----"
    echo
}

# Logging configuration
LOG_FILE="/tmp/permchange-$(date +%Y%m%d_%H%M%S).log"
SCRIPT_VERSION="v2025.4"

# Logging functions
log_info() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $msg" | tee -a "$LOG_FILE"
}

log_debug() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $msg" >> "$LOG_FILE"
}

# Initialize log file
init_logging() {
    echo
    echo "=============================================" > "$LOG_FILE"
    echo "PostgreSQL User Migration Script $SCRIPT_VERSION" >> "$LOG_FILE"
    echo "Execution started: $(date)" >> "$LOG_FILE"
    echo "Log file: $LOG_FILE" >> "$LOG_FILE"
    echo "=============================================" >> "$LOG_FILE"
    log_info "Logging initialized"
}

function check_prerequisites() {
    log_info "Performing prerequisite checks..."
    
    # Check if running as postgres user
    if [[ $(id -un) == "$USERNAME" ]]; then
        log_error "Do not run this script as the postgres user. Use root or sudo."
        exit 1
    fi
    log_info "✓ Script not running as postgres user"
    
    # Check if running as root/sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo privileges"
        exit 1
    fi
    log_info "✓ Running with root privileges"
    
    # # Check if PostgreSQL is stopped (DB servers)
    # if systemctl is-active --quiet postgresql@13-main.service; then
    #     log_error "PostgreSQL service is still running!"
    #     log_error "Please stop PostgreSQL first: sudo systemctl stop postgresql@13-main.service"
    #     exit 1
    # fi
    # log_info "✓ PostgreSQL service is stopped"
    
    # Check if PostgreSQL is stopped (container)
    if service postgresql status 2>/dev/null | grep -q "online"; then
        log_error "PostgreSQL is still running. Please stop it first:"
        log_error "sudo service postgresql stop"
        exit 1
    fi
    log_info "✓ PostgreSQL service is stopped"

    # Check if user exists
    if ! id "$USERNAME" &>/dev/null; then
        log_error "User '$USERNAME' does not exist!"
        exit 1
    fi
    log_info "✓ User '$USERNAME' exists"
    
    # Check current UID/GID
    CURRENT_UID=$(id -u $USERNAME)
    CURRENT_GID=$(id -g $USERNAME)
    log_info "Current UID/GID: $CURRENT_UID/$CURRENT_GID"
    
    # Check if new UID/GID are available
    if id "$NEW_USERID" &>/dev/null; then
        log_error "UID $NEW_USERID is already in use!"
        exit 1
    fi
    log_info "✓ Target UID $NEW_USERID is available"
    
    if getent group "$NEW_GROUPID" &>/dev/null; then
        log_error "GID $NEW_GROUPID is already in use!"
        exit 1
    fi
    log_info "✓ Target GID $NEW_GROUPID is available"
    
    log_info "All prerequisites passed ✓"
}

function create_backup() {
    local backup_dir="/tmp/postgres_backup_$(date +%Y%m%d_%H%M%S)"
    log_info "Creating backup directory: $backup_dir"
    
    mkdir -p "$backup_dir" || {
        log_error "Failed to create backup directory"
        exit 1
    }
    
    # Backup critical files
    log_info "Backing up /etc/passwd and /etc/group..."
    cp /etc/passwd "$backup_dir/passwd.bak" || {
        log_error "Failed to backup /etc/passwd"
        exit 1
    }
    
    cp /etc/group "$backup_dir/group.bak" || {
        log_error "Failed to backup /etc/group"
        exit 1
    }
    
    # Store ownership information
    log_info "Recording current file ownership..."
    find "$DB_DIR" -ls > "$backup_dir/ownership_db.txt" 2>/dev/null || true
    find "$CONFIG_DIR" -ls > "$backup_dir/ownership_config.txt" 2>/dev/null || true
    find "$LOG_DIR" -ls > "$backup_dir/ownership_log.txt" 2>/dev/null || true
    find "$HOME_DIR" -ls > "$backup_dir/ownership_home.txt" 2>/dev/null || true
    find "$VAR_RUN" -ls > "$backup_dir/ownership_run.txt" 2>/dev/null || true
    find "$USR_LIB" -ls > "$backup_dir/ownership_lib.txt" 2>/dev/null || true
    
    log_info "✓ Backup completed in $backup_dir"
    echo "$backup_dir" > /tmp/postgres_migration_backup_location
}

# Change user ID and group ID
function fix_ownership() {
    log_info "Changing user and group IDs..."
    
    # Change group first to avoid conflicts
    log_info "Modifying group ID from $(id -g $USERNAME) to $NEW_GROUPID"
    if ! groupmod -g $NEW_GROUPID $USERNAME; then
        log_error "Failed to change group ID"
        exit 1
    fi
    log_info "✓ Group ID changed successfully"
    
    # Change user ID
    log_info "Modifying user ID from $(id -u $USERNAME) to $NEW_USERID"
    if ! usermod -u $NEW_USERID $USERNAME; then
        log_error "Failed to change user ID"
        exit 1
    fi
    log_info "✓ User ID changed successfully"
    
    # Verify the changes
    NEW_UID_CHECK=$(id -u $USERNAME)
    NEW_GID_CHECK=$(id -g $USERNAME)
    if [[ "$NEW_UID_CHECK" != "$NEW_USERID" ]] || [[ "$NEW_GID_CHECK" != "$NEW_GROUPID" ]]; then
        log_error "UID/GID verification failed!"
        log_error "Expected: $NEW_USERID/$NEW_GROUPID, Got: $NEW_UID_CHECK/$NEW_GID_CHECK"
        exit 1
    fi
    log_info "✓ UID/GID changes verified: $NEW_USERID/$NEW_GROUPID"
}

# Fix ownership of known PostgreSQL directories
function fix_pg_ownership() {
    log_info "Fixing PostgreSQL directory ownership..."
    
    # Process each directory with error checking
    for dir in "$DB_DIR" "$CONFIG_DIR" "$HOME_DIR" "$LOG_DIR" "$VAR_RUN" "$USR_LIB"; do
        if [[ -d "$dir" ]]; then
            log_info "Processing directory: $dir"
            if chown -R postgres:postgres "$dir"; then
                log_info "✓ Fixed ownership for $dir"
            else
                log_error "Failed to fix ownership for $dir"
                exit 1
            fi
        else
            log_warning "Directory $dir does not exist, skipping"
        fi
    done
    
    # Handle hidden files explicitly
    log_info "Processing hidden files in $HOME_DIR..."
    find "$HOME_DIR" -name ".*" -exec chown postgres:postgres {} + 2>/dev/null || true
    
    log_info "✓ PostgreSQL directory ownership fix completed"
}

# Find and fix any remaining files with old UID (limited scope)
# Fix remaining files with old ownership
function fix_remaining_ownership() {
    log_info "Fixing remaining files with old ownership..."
    
    # Use find to locate and fix files with old UID/GID
    find / -user "$OLD_USERID" -exec chown "$USERNAME:$USERNAME" {} + 2>/dev/null || {
        log_warning "Some files couldn't be processed (permission denied or missing)"
    }
    
    find / -group "$OLD_GROUPID" -exec chgrp "$USERNAME" {} + 2>/dev/null || {
        log_warning "Some files couldn't be processed (permission denied or missing)"
    }
    
    log_info "✓ Remaining ownership fix completed"
}

# Shared Memory Cleanup - Clean orphaned segments from old UID
function fix_ipc() {
    log_info "Cleaning up shared memory segments..."
    
    # Find shared memory segments owned by old UID
    OLD_SEGMENTS=$(ipcs -m | grep "$OLD_USERID" | awk '{print $2}')
    
    if [[ -n "$OLD_SEGMENTS" ]]; then
        log_info "Found shared memory segments owned by old UID $OLD_USERID"
        echo "$OLD_SEGMENTS" | while read -r segment; do
            if ipcrm -m "$segment"; then
                log_info "✓ Removed shared memory segment: $segment"
            else
                log_warning "Failed to remove shared memory segment: $segment"
            fi
        done
    else
        log_info "No shared memory segments found for old UID $OLD_USERID"
    fi
    
    log_info "✓ Shared memory cleanup completed"
}

function verify_migration() {
    log_info "Verifying migration..."
    
    # Check user ID changed successfully
    CURRENT_UID=$(id -u $USERNAME)
    CURRENT_GID=$(id -g $USERNAME)
    
    if [[ "$CURRENT_UID" != "$NEW_USERID" ]]; then
        log_error "User ID migration failed. Current: $CURRENT_UID, Expected: $NEW_USERID"
        return 1
    fi
    
    if [[ "$CURRENT_GID" != "$NEW_GROUPID" ]]; then
        log_error "Group ID migration failed. Current: $CURRENT_GID, Expected: $NEW_GROUPID"
        return 1
    fi
    
    # Test directory access
    if ! sudo -u $USERNAME test -r "$DB_DIR"; then
        log_error "$USERNAME cannot read $DB_DIR"
        return 1
    fi
    
    if ! sudo -u $USERNAME test -w "$DB_DIR"; then
        log_error "$USERNAME cannot write $DB_DIR"
        return 1
    fi
    
    log_info "✓ Migration verification: PASSED"
    return 0
}

# Final check for any remaining files with old ownership
function verify_no_old_ownership() {
    echo "Checking for any remaining files with old ownership..."
    OLD_FILES=$(sudo find / -user $OLD_USERID 2>/dev/null | head -5)
    OLD_GROUPS=$(sudo find / -group $OLD_GROUPID 2>/dev/null | head -5)
    
    if [[ -n "$OLD_FILES" ]]; then
        echo "WARNING: Found files still owned by old UID $OLD_USERID:"
        echo "$OLD_FILES"
    else
        echo "✅ No files found with old UID $OLD_USERID"
    fi
    
    if [[ -n "$OLD_GROUPS" ]]; then
        echo "WARNING: Found files still owned by old GID $OLD_GROUPID:"
        echo "$OLD_GROUPS"
    else
        echo "✅ No files found with old GID $OLD_GROUPID"
    fi
}

function main() {
    init_logging
    
    log_info "PostgreSQL User Migration Script $SCRIPT_VERSION"
    log_info "================================================"
    
    checkvars
    check_prerequisites
    create_backup
    
    echo
    read -p "Proceed with migration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Migration cancelled by user"
        exit 0
    fi
    
    log_info "Starting migration process..."
    
    fix_ownership || { log_error "FAILED: User/Group ID change"; exit 1; }
    fix_pg_ownership || { log_error "FAILED: PostgreSQL directory ownership"; exit 1; }
    fix_remaining_ownership || { log_error "FAILED: Remaining file ownership"; exit 1; }
    fix_ipc || { log_error "FAILED: Shared memory cleanup"; exit 1; }
    verify_migration || { log_error "FAILED: Migration verification"; exit 1; }
    verify_no_old_ownership
    
    log_info "✅ Migration completed successfully!"
    log_info "You can now start PostgreSQL: sudo systemctl start postgresql"
    log_info "Log file saved at: $LOG_FILE"
    backup_location=$(cat /tmp/postgres_migration_backup_location 2>/dev/null || echo "Not found")
    log_info "Backup location: $backup_location"
    
    echo
    echo "✅ Migration completed successfully!"
    echo "You can now start PostgreSQL: sudo systemctl start postgresql"
    echo "Check the log file for details: $LOG_FILE"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi