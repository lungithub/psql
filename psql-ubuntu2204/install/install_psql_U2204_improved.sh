#!/bin/bash
#
# PostgreSQL Installation Script for Ubuntu 22.04
# This script installs and configures PostgreSQL with proper directory structure
# and permissions.
#
# Usage: ./install_psql_U2204_improved.sh [version]
# Example: ./install_psql_U2204_improved.sh 13
#
# Date: Mon 2025Jun16 
#

set -euo pipefail  # Exit on error, undefined vars, and pipeline errors

# Error trap handler
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Error handler function
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    log "Error occurred in script at line $line_no, exit code: $exit_code"
    log "Last command: $last_command"
    log "Function trace: $func_trace"
    exit "$exit_code"
}

# Default PostgreSQL version
PG_VERSION="${1:-13}"

# Directories
DATA_DIR="/db/pg${PG_VERSION}"
LOG_DIR="/var/log/postgres"
LOCK_DIR="/var/run/postgresql"
PSQL_BASE_DIR="/var/lib/postgresql/${PG_VERSION}"

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

# Add PostgreSQL repository and install packages
install_postgresql() {
    log "Adding PostgreSQL repository..."
    
    # More secure key handling using gpg and keyrings
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg || {
        log "Error: Failed to add PostgreSQL repository key"
        exit 1
    }

    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

    log "Updating package lists..."
    DEBIAN_FRONTEND=noninteractive apt-get update || { 
        log "Error: Failed to update package lists"
        exit 1
    }

    log "Installing PostgreSQL ${PG_VERSION}..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        postgresql-${PG_VERSION} \
        postgresql-contrib-${PG_VERSION} \
        python3-psycopg2 || {
        log "Error: Failed to install PostgreSQL packages"
        exit 1
    }
}

# Create and configure data directory
setup_data_directory() {
    log "Setting up data directory at ${DATA_DIR}..."
    mkdir -p "${DATA_DIR}" || { log "Error: Failed to create data directory"; exit 1; }
    chown -R postgres:postgres "${DATA_DIR}" || { log "Error: Failed to set ownership of data directory"; exit 1; }
    chmod 700 "${DATA_DIR}" || { log "Error: Failed to set permissions on data directory"; exit 1; }

    log "Configuring PostgreSQL data directory..."
    if [[ -d "${PSQL_BASE_DIR}/data" && ! -L "${PSQL_BASE_DIR}/data" ]]; then
        mv "${PSQL_BASE_DIR}/data" "${PSQL_BASE_DIR}/data_ORIG" || {
            log "Error: Failed to backup original data directory"
            exit 1
        }
    fi
    
    ln -sf "${DATA_DIR}" "${PSQL_BASE_DIR}/data" || {
        log "Error: Failed to create symlink to data directory"
        exit 1
    }
}

# Setup log directory
setup_log_directory() {
    log "Setting up log directory at ${LOG_DIR}..."
    mkdir -p "${LOG_DIR}" || { log "Error: Failed to create log directory"; exit 1; }
    chown postgres:postgres "${LOG_DIR}" || { log "Error: Failed to set ownership of log directory"; exit 1; }
    chmod 700 "${LOG_DIR}" || { log "Error: Failed to set permissions on log directory"; exit 1; }
}

# Setup lock directory
setup_lock_directory() {
    log "Setting up lock directory at ${LOCK_DIR}..."
    mkdir -p "${LOCK_DIR}" || { log "Error: Failed to create lock directory"; exit 1; }
    chown postgres:postgres "${LOCK_DIR}" || { log "Error: Failed to set ownership of lock directory"; exit 1; }
    chmod 755 "${LOCK_DIR}" || { log "Error: Failed to set permissions on lock directory"; exit 1; }
}

# Copy management files if they exist
copy_management_files() {
    if [[ -f "/hostdata/app/psql/install/psql_copy_management_files.sh" ]]; then
        log "Copying management files..."
        /hostdata/app/psql/install/psql_copy_management_files.sh || {
            log "Warning: Failed to copy management files"
            return 1
        }
    else
        log "Warning: Management files script not found"
        return 1
    fi
}

# Configure postgres environment if script exists
configure_postgres_environment() {
    if [[ -f "/hostdata/app/psql/install/psql_copy_sudo.sh" ]]; then
        log "Configuring postgres environment..."
        /hostdata/app/psql/install/psql_copy_sudo.sh || {
            log "Warning: Failed to configure postgres environment"
            return 1
        }
    else
        log "Warning: Environment configuration script not found"
        return 1
    fi
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    # Check directories and permissions
    local dirs=("${DATA_DIR}" "${LOG_DIR}" "${LOCK_DIR}")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log "Error: Directory $dir not found"
            return 1
        fi
        
        if [[ $(stat -c %U:%G "$dir") != "postgres:postgres" ]]; then
            log "Error: Incorrect ownership on $dir"
            return 1
        fi
    done

    # Check PostgreSQL binary
    if ! command -v psql &> /dev/null; then
        log "Error: PostgreSQL binary not found"
        return 1
    fi

    # Check PostgreSQL service
    if ! systemctl is-enabled postgresql &> /dev/null; then
        log "Enabling PostgreSQL service..."
        systemctl enable postgresql
    fi

    if ! systemctl is-active --quiet postgresql; then
        log "Starting PostgreSQL service..."
        systemctl start postgresql || {
            log "Error: Failed to start PostgreSQL service"
            return 1
        }
    fi

    # Try connecting to PostgreSQL
    if ! sudo -u postgres psql -c "\l" &> /dev/null; then
        log "Error: Unable to connect to PostgreSQL"
        return 1
    fi

    log "Installation verification complete"
    return 0
}

# Main function
main() {
    log "Starting PostgreSQL ${PG_VERSION} installation on Ubuntu 22.04..."
    
    check_root
    install_postgresql
    setup_data_directory
    setup_log_directory
    setup_lock_directory
    
    # Optional steps - don't fail if they don't succeed
    copy_management_files || true
    configure_postgres_environment || true
    
    if verify_installation; then
        log "PostgreSQL installation completed successfully"
        log "To start using PostgreSQL:"
        log "1. Connect to PostgreSQL: sudo -u postgres psql"
        log "2. Create a new database: CREATE DATABASE mydb;"
        log "3. Create a new user: CREATE USER myuser WITH ENCRYPTED PASSWORD 'mypass';"
        log "4. Grant privileges: GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;"
    else
        log "PostgreSQL installation completed with warnings"
        exit 1
    fi
}

# Run main function
main "$@"
