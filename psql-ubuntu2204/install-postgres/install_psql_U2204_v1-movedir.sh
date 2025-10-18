#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# PostgreSQL Installation Script for Ubuntu 22.04
# This script installs and configures PostgreSQL with proper directory structure
# and permissions.
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
# Usage: ./install_psql_U2204_improved.sh [version]
# Example: ./install_psql_U2204_improved.sh 13
#
# Date: Mon 2025Jun16 
# Date Modified: Sat 2025Oct18 14:19:03 PDT -- complete rewrite with movedir functionality
# - add logging functions
# - add error handling with trap
# - add OS check
# - improve PostgreSQL repository key handling
#
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
# Default PostgreSQL version
PG_VERSION="${1:-13}"

# Directories
PSQL_DEFAULT_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"
NEW_DATA_DIR="/db/mypg${PG_VERSION}"
LOG_DIR="/var/log/postgres"
LOCK_DIR="/var/run/postgresql"

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

# Check operating system
check_operating_system() {
    echo
    echo "----------------------------------------"
    echo " Checking Operating System "
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


# Add PostgreSQL repository and install packages
install_postgresql() {
    log_info "Proceeding with PostgreSQL installation..."
    echo
    echo "----------------------------------------"
    echo " Installing PostgreSQL ${PG_VERSION} "
    echo "----------------------------------------"
    echo
    log_info "Adding PostgreSQL repository..."
    
    # More secure key handling using gpg and keyrings
    # Overwrite keyring file without prompt
    if [[ -f /usr/share/keyrings/postgresql-keyring.gpg ]]; then
        rm -f /usr/share/keyrings/postgresql-keyring.gpg
    fi
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg

    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

    log_info "Updating package lists..."
    DEBIAN_FRONTEND=noninteractive apt-get update

    log_info "Installing PostgreSQL ${PG_VERSION}..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        postgresql-${PG_VERSION} \
        postgresql-contrib-${PG_VERSION} \
        python3-psycopg2
}

# Create and configure custom data directory
# The reason for moving the data directory is often to place it on a different disk or partition  
# that may have better performance, more space, or specific backup strategies.   
setup_data_directory() {
    echo
    echo "----------------------------------------"
    echo " Setting up Data Directory "
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

    log_info "Copying contents from ${PSQL_DEFAULT_DATA_DIR} to ${NEW_DATA_DIR}..."
    if [[ -d "${PSQL_DEFAULT_DATA_DIR}" && ! -L "${PSQL_DEFAULT_DATA_DIR}" ]]; then
        cp -a "${PSQL_DEFAULT_DATA_DIR}/." "${NEW_DATA_DIR}/"
        mv "${PSQL_DEFAULT_DATA_DIR}" "${PSQL_DEFAULT_DATA_DIR}_ORIG"
    fi

    log_info "Creating symlink from ${PSQL_DEFAULT_DATA_DIR} to ${NEW_DATA_DIR}..."
    ln -sf "${NEW_DATA_DIR}" "${PSQL_DEFAULT_DATA_DIR}"
}

# Setup log directory
setup_log_directory() {
    echo
    echo "----------------------------------------"
    echo " Setting up Log Directory "
    echo "----------------------------------------"
    echo
    log_info "Setting up log directory at ${LOG_DIR}..."
    mkdir -p "${LOG_DIR}"
    chown postgres:postgres "${LOG_DIR}"
    chmod 700 "${LOG_DIR}"
}

# Setup lock directory
setup_lock_directory() {
    echo
    echo "----------------------------------------"
    echo " Setting up Lock Directory "
    echo "----------------------------------------"
    echo
    log_info "Setting up lock directory at ${LOCK_DIR}..."
    mkdir -p "${LOCK_DIR}"
    chown postgres:postgres "${LOCK_DIR}"
    chmod 755 "${LOCK_DIR}"
}

initialize_database() {
    echo
    echo "----------------------------------------"
    echo " Initializing PostgreSQL Database "
    echo "----------------------------------------"
    echo
    log_info "Initializing database cluster..."
    sudo -u postgres /usr/lib/postgresql/${PG_VERSION}/bin/initdb -D "${NEW_DATA_DIR}" || {
        log_error "Database initialization failed"
        exit 1
    }
}

# Copy management files if they exist
copy_management_files() {
    echo
    echo "----------------------------------------"
    echo " Copying PostgreSQL Management Files "
    echo "----------------------------------------"
    echo
    if [[ -f "/hostdata/app/psql/psql-ubuntu2204/install-postgres/copy_psql_management_files.sh" ]]; then
        log_info "Copying management files..."
        /hostdata/app/psql/psql-ubuntu2204/install-postgres/copy_psql_management_files.sh || {
            log_warning "Failed to copy management files"
            return 1
        }
    else
        log_warning "Management files script not found"
        return 1
    fi
}

# Configure postgres environment if script exists
configure_postgres_sudo() {
    echo
    echo "----------------------------------------"
    echo " Configuring PostgreSQL Sudo Environment "
    echo "----------------------------------------"
    echo
    if [[ -f "/hostdata/app/psql/psql-ubuntu2204/install-postgres/psql_postgres_sudo.sh" ]]; then
        log_info "Configuring postgres sudo environment..."
        /hostdata/app/psql/psql-ubuntu2204/install-postgres/psql_postgres_sudo.sh || {
            log_warning "Failed to configure postgres sudo environment"
            return 1
        }
    else
        log_warning "Sudo configuration script not found"
        return 1
    fi
}

configure_postgres_environment() {
    echo
    echo "----------------------------------------"
    echo " Configuring PostgreSQL Environment "
    echo "----------------------------------------"
    echo
    if [[ -f "/hostdata/app/psql/psql-ubuntu2204/install-postgres/psql_postgres_environment.sh" ]]; then
        log_info "Configuring postgres environment..."
        /hostdata/app/psql/psql-ubuntu2204/install-postgres/psql_postgres_environment.sh || {
            log_warning "Failed to configure postgres environment"
            return 1
        }
    else
        log_warning "Environment configuration script not found"
        return 1
    fi
}

# Verify installation
verify_installation() {
    echo
    echo "----------------------------------------"
    echo " Verifying Installation "
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

    # Check PostgreSQL binary
    if ! command -v psql &> /dev/null; then
        log_error "PostgreSQL binary not found"
        return 1
    fi

    # Check PostgreSQL service
    if ! systemctl is-enabled postgresql &> /dev/null; then
        log_info "Enabling PostgreSQL service..."
        systemctl enable postgresql
    fi

    if ! systemctl is-active --quiet postgresql; then
        log_info "Starting PostgreSQL service..."
        systemctl start postgresql
    fi

    # Try connecting to PostgreSQL
    if ! sudo -u postgres psql -c "\l" &> /dev/null; then
        log_error "Unable to connect to PostgreSQL"
        return 1
    fi

    log_success "Installation verification complete"
    return 0
}

# Function to check existing settings
# Check how much time passed between start and end
calculate_time_difference() {
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
    echo " PostgreSQL Installation Script "
    echo "----------------------------------------"
    echo
    log_info "Starting PostgreSQL ${PG_VERSION} installation on Ubuntu 22.04..."
    
    if which psql > /dev/null; then
        log_info "psql is already installed. Skipping installation."
        exit 0
    fi

    check_root
    install_postgresql
    setup_data_directory
    setup_log_directory
    setup_lock_directory
    
    # Optional steps - don't fail if they don't succeed
    copy_management_files || true
    configure_postgres_sudo || true
    configure_postgres_environment || true

    if verify_installation; then
        log_success "PostgreSQL installation completed successfully"
        log_info "To start using PostgreSQL:"
        log_info "1. Connect to PostgreSQL: sudo -u postgres psql"
        log_info "2. Create a new database: psql -c \"CREATE DATABASE mydb;\""
        log_info "3. Create a new user: psql -c \"CREATE USER myuser WITH ENCRYPTED PASSWORD 'mypass';\""
        log_info "4. Grant privileges: psql -c \"GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;\""
    else
        log_warning "PostgreSQL installation completed with warnings"
        exit 1
    fi

    sleep 5

    local end_time=$(date +"%Y-%m-%d %H:%M:%S")

    calculate_time_difference "$start_time" "$end_time"

}

# Run main function
main "$@"
