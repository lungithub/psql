#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# PURPOSE: Copy PostgreSQL management scripts to the appropriate directory
#
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
set -euo pipefail  # Exit on error, undefined vars, and pipeline errors

BIN_DIR=/var/lib/pgsql/bin
BASEDIR=/hostdata/app/psql/psql-ubuntu2204
FILES=${BASEDIR}/postgres-config-files

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

function create-bin-dir() {
    log "Creating bin directory at ${BIN_DIR}..."
    # Create directory if it doesn't exist
    mkdir -p "${BIN_DIR}"
    chown postgres:postgres "${BIN_DIR}"
    log "Directory ${BIN_DIR} created successfully"
}

declare -a files=(pstart.sh pstop.sh pstatus.sh psreload.sh)

function copy-management-files() {
    log "Starting copy of PostgreSQL management files..."
    
    # Loop through each file in the array
    for file in "${files[@]}"; do
        local base_name="${file%.sh}"  # Remove .sh extension for symlink name
        
        if [[ -f "${FILES}/${file}" ]]; then
            log "Copying ${file}..."
            if cp "${FILES}/${file}" "${BIN_DIR}"; then
                # Create symlink without .sh extension
                ln -sf "${BIN_DIR}/${file}" "/usr/local/bin/${base_name}"
                log "Successfully copied and linked ${file}"
            else
                log "Error: Failed to copy ${file}"
            fi
        else
            log "Warning: ${file} not found at ${FILES}/${file}"
        fi
    done

    log "Change permissions to postgres user..."
    chown -R postgres:postgres "${BIN_DIR}"
    chmod 700 "${BIN_DIR}"/*

    echo
    log "Verify startup scripts."
    echo
    ls -l "${BIN_DIR}"/pst* || log "Unable to copy psql management files."
    echo

    # back to top root homedir
    cd /root
}

main() {
    log "Starting PostgreSQL management files copy script..."
    
    check_root
    create-bin-dir
    copy-management-files
    
    log "Management files copy completed successfully"
}

# Run main function
main "$@"
