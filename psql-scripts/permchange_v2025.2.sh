#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# PostgreSQL User Migration Script v2025.1
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
NEW_USERID=153
NEW_GROUPID=153
OLD_USERID=152
OLD_GROUPID=152

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

function check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check if running as postgres user
    if [[ $(id -un) == "$USERNAME" ]]; then
        echo "ERROR: Do not run this script as the postgres user. Use root or sudo."
        exit 1
    fi
    # Check if running as root/sudo
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run with sudo privileges"
        exit 1
    fi
    
    # Check if PostgreSQL is stopped
    # if systemctl is-active --quiet postgresql; then
    #     echo "ERROR: PostgreSQL is still running. Please stop it first:"
    #     echo "sudo systemctl stop postgresql"
    #     exit 1
    # fi
    if service postgresql status 2>/dev/null | grep -q "online"; then
        echo "ERROR: PostgreSQL is still running. Please stop it first:"
        echo "sudo service postgresql stop"
        exit 1
    fi
    
    # Check if new UID is available
    if getent passwd $NEW_USERID >/dev/null 2>&1; then
        echo "ERROR: UID $NEW_USERID is already in use. Choose a new one."
        exit 1
    fi
    
    # Check if new GID is available  
    if getent group $NEW_GROUPID >/dev/null 2>&1; then
        echo "ERROR: GID $NEW_GROUPID is already in use. Choose a new one."
        exit 1
    fi
    
    # Recommend matching UID and GID for system users
    if [[ "$NEW_USERID" != "$NEW_GROUPID" ]]; then
        echo "WARNING: UID ($NEW_USERID) and GID ($NEW_GROUPID) are different."
        echo "For system users like PostgreSQL, it's recommended to use matching values."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Please update NEW_GROUPID=$NEW_USERID in the script"
            exit 1
        fi
    fi
    
    # Verify directories exist
    for dir in "$DB_DIR" "$CONFIG_DIR" "$LOG_DIR" "$HOME_DIR" "$VAR_RUN" "$USR_LIB"; do
        if [[ ! -d "$dir" ]]; then
            echo "ERROR: Directory $dir does not exist"
            exit 1
        fi
    done
    
    echo "Prerequisites check: PASSED"
}

function create_backup() {
    echo "Creating backup of current state..."
    BACKUP_DIR="/tmp/postgres_migration_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup system files
    cp /etc/passwd "$BACKUP_DIR/"
    cp /etc/group "$BACKUP_DIR/"
    cp /etc/shadow "$BACKUP_DIR/"
    
    # Document current file ownership
    find "$DB_DIR" "$CONFIG_DIR" "$LOG_DIR" "$HOME_DIR" "$VAR_RUN" "$USR_LIB" -ls > "$BACKUP_DIR/file_ownership.txt" 2>/dev/null
    
    echo "Backup created at: $BACKUP_DIR"
    echo "BACKUP_DIR=$BACKUP_DIR" > /tmp/postgres_migration_backup_path
}

# Change user ID and group ID
function fix_ownership() {
    echo "Changing user and group IDs..."
    sudo usermod -u $NEW_USERID $USERNAME
    sudo groupmod -g $NEW_GROUPID $USERNAME
    echo "User/Group ID changes completed"
}

# Fix ownership of known PostgreSQL directories
function fix_pg_ownership() {
    echo "Fixing PostgreSQL directory ownership..."
    sudo chown -R postgres:postgres $DB_DIR
    sudo chown -R postgres:postgres $CONFIG_DIR
    sudo chown -R postgres:postgres $HOME_DIR
    sudo chown -R postgres:postgres $LOG_DIR
    sudo chown -R postgres:postgres $VAR_RUN
    sudo chown -R postgres:postgres $USR_LIB
    echo "PostgreSQL directory ownership fixed"
}

# Find and fix any remaining files with old UID (limited scope)
function fix_remaining_ownership() {
    echo "Fixing remaining file ownership..."
    sudo find /home /opt /usr/local /var -user $OLD_USERID -exec chown $USERNAME {} \; 2>/dev/null
    sudo find /home /opt /usr/local /var -group $OLD_GROUPID -exec chgrp $USERNAME {} \; 2>/dev/null
    echo "Remaining file ownership fixed"
}

# Shared Memory Cleanup - Clean orphaned segments from old UID
function fix_ipc() {
    echo "Cleaning up shared memory segments..."
    sudo ipcs -m | grep $OLD_USERID | awk '{print $2}' | xargs -r sudo ipcrm -m
    echo "Shared memory cleanup completed"
}

function verify_migration() {
    echo "Verifying migration..."
    
    # Check user ID changed successfully
    CURRENT_UID=$(id -u $USERNAME)
    CURRENT_GID=$(id -g $USERNAME)
    
    if [[ "$CURRENT_UID" != "$NEW_USERID" ]]; then
        echo "ERROR: User ID migration failed. Current: $CURRENT_UID, Expected: $NEW_USERID"
        return 1
    fi
    
    if [[ "$CURRENT_GID" != "$NEW_GROUPID" ]]; then
        echo "ERROR: Group ID migration failed. Current: $CURRENT_GID, Expected: $NEW_GROUPID"
        return 1
    fi
    
    # Test directory access
    sudo -u $USERNAME test -r "$DB_DIR" || { echo "ERROR: $USERNAME cannot read $DB_DIR"; return 1; }
    sudo -u $USERNAME test -w "$DB_DIR" || { echo "ERROR: $USERNAME cannot write $DB_DIR"; return 1; }
    
    echo "Migration verification: PASSED"
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
    echo
    echo "PostgreSQL User Migration Script v2025.1"
    echo "========================================"
    
    checkvars
    check_prerequisites
    create_backup
    
    read -p "Proceed with migration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Migration cancelled"
        exit 0
    fi
    
    echo "Starting migration process..."
    fix_ownership || { echo "FAILED: User/Group ID change"; exit 1; }
    fix_pg_ownership || { echo "FAILED: PostgreSQL directory ownership"; exit 1; }
    fix_remaining_ownership || { echo "FAILED: Remaining file ownership"; exit 1; }
    fix_ipc || { echo "FAILED: Shared memory cleanup"; exit 1; }
    verify_migration || { echo "FAILED: Migration verification"; exit 1; }
    verify_no_old_ownership
    
    echo
    echo "✅ Migration completed successfully!"
    echo "You can now start PostgreSQL: sudo systemctl start postgresql"
    echo
    echo "Backup location: $(cat /tmp/postgres_migration_backup_path 2>/dev/null)"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi