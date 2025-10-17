#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# PURPOSE: Configure sudo access for postgres user
#
# I have a preconfigured GROUPS and SUDOERS file with the postgres
# user. I just copy those files to the container to enable sudo 
# for postgres.
#
# Perms for reference:
# /etc/group: -rw-r--r-- 1 root root 373 Jan  9 01:53 /etc/group
# /etc/sudoers: -r--r----- 1 root root 440 /etc/sudoers
#
# CONFIGURATION ARRAY FORMAT:
# The config_files array contains colon-separated entries in the format:
#   "source_file:destination_file:permissions"
# 
# Example: "etc_sudoers:/etc/sudoers:440"
#   - source_file = "etc_sudoers" (file in ${FILES_DIR}/)
#   - destination_file = "/etc/sudoers" (target system file)
#   - permissions = "440" (octal permissions to set)
#
# The script uses IFS=':' read to parse each entry and extract these three
# variables for processing in the copy_config_files() function.
#
# The script uses a function to test sudo access for the postgres user.
#
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
set -euo pipefail  # Exit on error, undefined vars, and pipeline errors

# Configuration
BASEDIR=/hostdata/app/psql/psql-ubuntu2204
FILES_DIR=${BASEDIR}/files

# Error trap handler
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Error handler function
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Script failed at line $line_no with exit code: $exit_code" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Failed command: $last_command" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Function call stack: ${func_trace#::}" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Bash line numbers: $bash_lineno" >&2
    exit "$exit_code"
}

# Log messages with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Error: This script must be run as root"
        exit 1
    fi
}

# Array of configuration files to process
declare -a config_files=(
    "etc_sudoers:/etc/sudoers:440"
    "etc_group:/etc/group:644"
)

# Function to backup and copy configuration files
copy_config_files() {
    log "Starting configuration files copy process..."
    
    for config_entry in "${config_files[@]}"; do
        # Parse the configuration entry: source_file:dest_file:permissions
        IFS=':' read -r source_file dest_file permissions <<< "$config_entry"
        
        local source_path="${FILES_DIR}/${source_file}"
        local backup_file="${dest_file}.$$"
        
        if [[ -f "$source_path" ]]; then
            log "Processing ${source_file} -> ${dest_file}..."
            
            # Create backup of original file
            if [[ -f "$dest_file" ]]; then
                log "Creating backup: ${dest_file} -> ${backup_file}"
                cp "$dest_file" "$backup_file"
            fi
            
            # Copy new configuration file
            log "Copying ${source_path} to ${dest_file}"
            cp "$source_path" "$dest_file"
            
            # Set proper permissions
            log "Setting permissions ${permissions} on ${dest_file}"
            chmod "$permissions" "$dest_file"
            
            # Verify postgres user is in the file
            verify_postgres_config "$dest_file" "$source_file"
            
        else
            log "Warning: Source file not found: ${source_path}"
        fi
    done
    
    log "Configuration files copy completed successfully"
}

# Function to verify postgres user configuration
verify_postgres_config() {
    local config_file="$1"
    local file_type="$2"
    
    log "Verifying postgres user in ${file_type}..."
    echo
    ls -l "$config_file"
    
    if grep -q postgres "$config_file"; then
        log "✓ postgres user found in ${config_file}"
    else
        log "⚠ WARNING: postgres user not found in ${config_file}"
    fi
    echo
}

# Function to verify postgres user can actually use sudo
verify_sudo() {
    log "Testing sudo access for postgres user..."
    
    # Test if postgres user can execute a sudo command
    if sudo -u postgres sudo -n tail -1 /etc/shadow >/dev/null 2>&1; then
        log "✓ SUCCESS: postgres user can execute sudo commands"
        log "✓ Sudo configuration is working correctly"
    else
        log "⚠ WARNING: postgres user cannot execute sudo commands"
        log "⚠ This may be due to:"
        log "   - sudoers file not properly configured"
        log "   - postgres user not in sudo group"
        log "   - sudo requiring password (NOPASSWD not set)"
        
        # Try a more detailed test
        log "Attempting detailed sudo test..."
        if sudo -u postgres sudo -l >/dev/null 2>&1; then
            log "✓ postgres user has some sudo privileges"
        else
            log "✗ postgres user has no sudo privileges"
        fi
    fi
    echo
}

# Main function
main() {
    log "Starting PostgreSQL sudo configuration setup..."
    
    check_root
    copy_config_files
    verify_sudo
    
    log "PostgreSQL sudo configuration completed successfully"
}

# Run main function
main "$@"  