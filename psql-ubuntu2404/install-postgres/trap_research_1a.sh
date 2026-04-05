#!/bin/bash
#
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
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Script failed at line $line_no with exit code: $exit_code" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Failed command: $last_command" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Function call stack: ${func_trace#::}" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Bash line numbers: $bash_lineno" >&2
    exit "$exit_code"
}

# Directories
LOG_DIR="/var/log/postgres"

# Log messages with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}


# Setup log directory
setup_log_directory() {
    log "Setting up log directory at ${LOG_DIR}..."
    mkdir -p "${LOG_DIR}"
    chown postgres:postgres "${LOG_DIR}"
    chmod 700 "${LOG_DIR}"
}


# Main function
main() {
    log "Starting PostgreSQL ${PG_VERSION} installation on Ubuntu 22.04..."
    
    setup_log_directory
    
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
