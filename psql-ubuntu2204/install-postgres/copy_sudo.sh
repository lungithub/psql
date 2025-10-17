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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# Error trap handler
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Error handler function
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} Script failed at line $line_no with exit code: $exit_code" >&2
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} Failed command: $last_command" >&2
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} Function call stack: ${func_trace#::}" >&2
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} Bash line numbers: $bash_lineno" >&2
    exit "$exit_code"
}

# Logging functions
log_info() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $1"
}


# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
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
    log_info "Starting configuration files copy process..."
    
    for config_entry in "${config_files[@]}"; do
        # Parse the configuration entry: source_file:dest_file:permissions
        IFS=':' read -r source_file dest_file permissions <<< "$config_entry"
        
        local source_path="${FILES_DIR}/${source_file}"
        local backup_file="${dest_file}.$$"
        
        if [[ -f "$source_path" ]]; then
            log_info "Processing ${source_file} -> ${dest_file}..."
            
            # Create backup of original file
            if [[ -f "$dest_file" ]]; then
                log_info "Creating backup: ${dest_file} -> ${backup_file}"
                cp "$dest_file" "$backup_file"
            fi
            
            # Copy new configuration file
            log_info "Copying ${source_path} to ${dest_file}"
            cp "$source_path" "$dest_file"
            
            # Set proper permissions
            log_info "Setting permissions ${permissions} on ${dest_file}"
            chmod "$permissions" "$dest_file"
            
            # Verify postgres user is in the file
            verify_postgres_config "$dest_file" "$source_file"
            
        else
            log_warning "Source file not found: ${source_path}"
        fi
    done
    
    log_success "Configuration files copy completed successfully"
}

# Function to verify postgres user configuration
verify_postgres_config() {
    local config_file="$1"
    local file_type="$2"
    
    log_info "Verifying postgres user in ${file_type}..."
    echo
    ls -l "$config_file"
    
    if grep -q postgres "$config_file"; then
        log_success "postgres user found in ${config_file}"
    else
        log_warning "postgres user not found in ${config_file}"
    fi
    echo
}

# Function to verify postgres user can actually use sudo
verify_sudo() {
    log_info "Testing sudo access for postgres user..."
    
    # Test if postgres user can execute a sudo command
    if sudo -u postgres sudo -n tail -1 /etc/shadow >/dev/null 2>&1; then
        log_success "postgres user can execute sudo commands"
        log_success "Sudo configuration is working correctly"
    else
        log_warning "postgres user cannot execute sudo commands"
        log_warning "This may be due to:"
        log_warning "   - sudoers file not properly configured"
        log_warning "   - postgres user not in sudo group"
        log_warning "   - sudo requiring password (NOPASSWD not set)"
        
        # Try a more detailed test
        log_info "Attempting detailed sudo test..."
        if sudo -u postgres sudo -l >/dev/null 2>&1; then
            log_success "postgres user has some sudo privileges"
        else
            log_error "postgres user has no sudo privileges"
        fi
    fi
    echo
}

# Main function
main() {
    log_info "Starting PostgreSQL sudo configuration setup..."
    
    check_root
    copy_config_files
    verify_sudo
    
    log_success "PostgreSQL sudo configuration completed successfully"
}

# Run main function
main "$@"  