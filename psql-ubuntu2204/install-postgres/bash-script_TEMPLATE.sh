#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#
# PURPOSE: aaaa
#
# ------------------------------------------------------------------
# The 'trap' line is placed near the top of the script, right after set -euo pipefail.
#
# It sets up a trap for the ERR signal, which is triggered whenever a command returns a non-zero exit status (i.e., an error occurs).
# When an error happens, the trap calls the error_handler function, passing it:
# - The exit code ($?)
# - The current line number ($LINENO)
# - The Bash line number array ($BASH_LINENO)
# - The last command executed ("$BASH_COMMAND")
# - The function call stack (using FUNCNAME)
#
# This provides detailed error reporting and debugging information whenever any error occurs in the script, making troubleshooting much easier.
# ------------------------------------------------------------------
#
# Usage: ./myscript.sh [version]
# Example: ./myscript.sh aaa
#
# Date Modified: Sat 2025Oct18 14:19:03 PDT -- aaaa
# - aaa
# - aaa
# Author: devesplabs
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

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
#
# Default version
PG_VERSION="${1:-13}"

# Directories
PSQL_DEFAULT_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"

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

# aa
check_operating_system() {
    echo
    echo "----------------------------------------"
    echo "  :: $FUNCNAME :: Checking Operating System "
    echo "----------------------------------------"
    echo
    if [[ "$(lsb_release -is)" != "Ubuntu" ]]; then
        log_error "This script is designed to run on Ubuntu"
        exit 1
    fi

    if [[ "$(lsb_release -rs)" != "22.04" ]]; then
        log_warning "This script is optimized for Ubuntu 22.04"
    fi
}


# aaa
myfunction1() {
    echo
    echo "----------------------------------------"
    echo "  :: $FUNCNAME :: Processing aaa "
    echo "----------------------------------------"
    echo
    log_info "Adding aaa..."

}

# aaa  
myfunction2() {
    echo
    echo "----------------------------------------"
    echo "  :: $FUNCNAME :: Setting up Data Directory "
    echo "----------------------------------------"
    echo
    log_info "Creating new data directory at ${NEW_DATA_DIR}..."
    mkdir -p "${NEW_DATA_DIR}"
    chown -R postgres:postgres "${NEW_DATA_DIR}"
    chmod 700 "${NEW_DATA_DIR}"

    # Check if symlink already exists
    if [[ -L "${PSQL_DEFAULT_DATA_DIR}" ]]; then
        log_error "Symlink ${PSQL_DEFAULT_DATA_DIR} already exists. Aborting to prevent overwrite."
        exit 1
    fi
}


# aaa
myfunction3() {
    echo
    echo
    echo "----------------------------------------"
    echo "  $FUNCNAME :: Verify aaa"
    echo "----------------------------------------"
    echo
    log_info "Verifying installation..."
    
    # Check directories and permissions
    local dirs=("${NEW_DATA_DIR}" "${LOG_DIR}" "${LOCK_DIR}")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Directory $dir not found"
            return 1
        fi
        
        if [[ $(stat -c %U:%G "$dir") != "postgres:postgres" ]]; then
            log_error "Incorrect ownership on $dir"
            return 1
        fi
    done

    # Check PostgreSQL service
    if ! systemctl is-enabled postgresql &> /dev/null; then
        log_info "Enabling PostgreSQL service..."
        systemctl enable postgresql
    fi

    log_success "Installation verification complete"
    return 0
}

# Function to check existing settings
# Check how much time passed between start and end
calculate_time_difference() {
    echo
    echo "----------------------------------------"
    echo "  :: $FUNCNAME :: aaa"
    echo "----------------------------------------"
    echo
    log_info "Calculating installation time difference..."
    local start_time=$1
    local end_time=$2

    start_seconds=$(date -d "$start_time" +%s)
    end_seconds=$(date -d "$end_time  " +%s)
    diff_seconds=$((end_seconds - start_seconds))
    
    readable_time_human=$(date -u -d @"$diff_seconds" +"%H:%M:%S")
    log_info "Total installation time: $readable_time_human (HH:MM:SS)"
    echo
    echo "Start time: $start_time"
    echo "End time:   $end_time"
    echo "Total duration: $diff_seconds seconds"
}

# Main function
main() {
    local start_time=$(date +"%Y-%m-%d %H:%M:%S")

    echo
    echo "----------------------------------------"
    echo "  :: FUNCTION :: $FUNCNAME "
    echo "----------------------------------------"
    echo
    log_info "Starting PostgreSQL ${PG_VERSION} installation on Ubuntu 22.04..."

    check_root
    check_operating_system

    if which psql > /dev/null; then
        log_info "psql is already installed. Skipping installation."
        exit 0
    fi
    
    myfunction1
    myfunction2

    # Optional steps - don't fail if they don't succeed
    myfunction3 || true

    if myfunction3; then
        log_success "completed successfully"
        log_info "To start using PostgreSQL:"
        log_info "1. Connect to PostgreSQL: sudo -u postgres psql"
        log_info "2. Create a new database: psql -c \"CREATE DATABASE mydb;\""
        log_info "3. Create a new user: psql -c \"CREATE USER myuser WITH ENCRYPTED PASSWORD 'mypass';\""
        log_info "4. Grant privileges: psql -c \"GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;\""
    else
        log_warning "completed with warnings"
        exit 1
    fi

    local end_time=$(date +"%Y-%m-%d %H:%M:%S")

    calculate_time_difference "$start_time" "$end_time"

}

# Run main function
main "$@"
