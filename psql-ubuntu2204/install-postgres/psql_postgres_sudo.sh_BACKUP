#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# PURPOSE: Configure sudo access for postgres user
#
# The script uses a function to test sudo access for the postgres user.
#
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
set -euo pipefail  # Exit on error, undefined vars, and pipeline errors

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


# Function to verify postgres user configuration
setup_postgres_sudo_config() {
    # Add postgres to admin group (sudo or wheel)
    if getent group sudo > /dev/null; then
        log_info "Adding postgres to sudo group"
        usermod -aG sudo postgres
    elif getent group wheel > /dev/null; then
        log_info "Adding postgres to wheel group"
        usermod -aG wheel postgres
    else
        log_warning "No sudo or wheel group found; skipping group addition"
    fi

    # Set up passwordless sudo for postgres
    SUDOERS_FILE="/etc/sudoers.d/postgres"
    echo "postgres ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    log_success "Passwordless sudo configured for postgres in $SUDOERS_FILE"
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
    setup_postgres_sudo_config
    verify_sudo
    
    log_success "PostgreSQL sudo configuration completed successfully"
}

# Run main function
main "$@"