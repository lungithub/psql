#!/bin/bash
: <<'COMMENT'
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

PURPOSE: Copy PostgreSQL management scripts to the appropriate directory

Copies postgres-config-files (pstart.sh, pstop.sh, pstatus.sh, psreload.sh)
to BIN_DIR and symlinks them into /usr/local/bin without the .sh extension.
Also copies postgresql.conf and pg_hba.conf to the live config directory.

Paths are resolved dynamically from BASH_SOURCE so this script works regardless
of working directory or container mount point.

CALLED BY: install_psql_U2404_v1-movedir.sh (copy_management_files step)
           Can also be run standalone as root.

VERSION RESOLUTION (PG_VERSION):
  This script sources pg-config.env directly — it does NOT inherit PG_VERSION
  from a caller. Resolution priority (highest → lowest):
    1. Shell env var    export PG_VERSION=16
    2. pg-config.env    PG_VERSION=13         ← team default, edit here
    3. Script default   13                    ← last resort fallback

  When called by the install script, the install script has already sourced
  pg-config.env. However, since this script also sources it independently,
  it is safe to run standalone without the install script.

Revised: Sat 2026Apr04 12:00:00 PST
Author: devesplabs
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
COMMENT

set -euo pipefail  # Exit on error, undefined vars, and pipeline errors

# Dynamic path resolution — works regardless of working directory or mount point
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# Source shared config for PG_VERSION
PG_CONFIG_FILE="${SCRIPT_DIR}/pg-config.env"
if [[ -f "${PG_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    . "${PG_CONFIG_FILE}"
fi
unset PG_CONFIG_FILE

# Version and user — env var overrides pg-config.env, fallback if neither set
PG_VERSION="${PG_VERSION:-13}"

# Target PostgreSQL OS user — override via env var if needed
PG_USER="${PG_USER:-postgres}"

# Paths derived from resolved variables — no hardcoding
BIN_DIR="/var/lib/postgresql/bin"
FILES="${SCRIPT_DIR}/../postgres-config-files"
ETC_POSTGRESQL_DIR="/etc/postgresql/${PG_VERSION}/main"

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

copy_config_files() {
    echo
    echo "----------------------------------------"
    echo " Copy PostgreSQL Configuration Files    "
    echo "----------------------------------------"
    echo
    log_info "Source : ${FILES}"
    log_info "Target : ${ETC_POSTGRESQL_DIR}"
    log_info "Starting copy of PostgreSQL configuration files..."
    cp "${FILES}/primary_postgresql.conf" "${ETC_POSTGRESQL_DIR}/postgresql.conf"
    cp "${FILES}/pg_hba.conf"             "${ETC_POSTGRESQL_DIR}/pg_hba.conf"
    chown "${PG_USER}:${PG_USER}" "${ETC_POSTGRESQL_DIR}/postgresql.conf"
    chown "${PG_USER}:${PG_USER}" "${ETC_POSTGRESQL_DIR}/pg_hba.conf"
    chmod 640 "${ETC_POSTGRESQL_DIR}/postgresql.conf"
    chmod 640 "${ETC_POSTGRESQL_DIR}/pg_hba.conf"
    log_success "PostgreSQL configuration files copied successfully"
}

create_bin_dir() {
    log_info "Creating bin directory at ${BIN_DIR}..."
    mkdir -p "${BIN_DIR}"
    chown "${PG_USER}:${PG_USER}" "${BIN_DIR}"
    log_success "Directory ${BIN_DIR} created successfully"
}

declare -a MGMT_FILES=(pstart.sh pstop.sh pstatus.sh psreload.sh)

copy_management_files() {
    echo
    echo "----------------------------------------"
    echo " Copy PostgreSQL Management Files       "
    echo "----------------------------------------"
    echo
    log_info "Source : ${FILES}"
    log_info "Target : ${BIN_DIR}"
    log_info "Starting copy of PostgreSQL management files..."

    for file in "${MGMT_FILES[@]}"; do
        local base_name="${file%.sh}"  # Remove .sh extension for symlink name

        if [[ -f "${FILES}/${file}" ]]; then
            log_info "Copying ${file}..."
            if cp "${FILES}/${file}" "${BIN_DIR}"; then
                ln -sf "${BIN_DIR}/${file}" "/usr/local/bin/${base_name}"
                log_success "Copied and linked: ${file} → /usr/local/bin/${base_name}"
            else
                log_error "Failed to copy ${file}"
            fi
        else
            log_warning "${file} not found at ${FILES}/${file}"
        fi
    done

    log_info "Setting ownership and permissions on ${BIN_DIR}..."
    chown -R "${PG_USER}:${PG_USER}" "${BIN_DIR}"
    chmod 700 "${BIN_DIR}"/*

    echo
    log_info "Verify management scripts:"
    echo
    ls -l "${BIN_DIR}"/pst* || log_warning "Unable to list psql management files."
    echo

    cd /root
}

main() {
    log_info "Starting PostgreSQL management files copy script..."
    log_info "PG_VERSION : ${PG_VERSION}"
    log_info "PG_USER    : ${PG_USER}"
    log_info "FILES      : ${FILES}"

    check_root
    copy_config_files
    create_bin_dir
    copy_management_files

    log_success "Management files copy completed successfully"
}

# Run main function
main "$@"
