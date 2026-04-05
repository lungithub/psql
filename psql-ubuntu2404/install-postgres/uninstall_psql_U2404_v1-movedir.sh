#!/bin/bash
: <<'COMMENT'
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
PostgreSQL Uninstallation Script for Ubuntu 24.04
This script stops, removes, and cleans up PostgreSQL and all associated
directories, repository sources, and GPG keys created by the companion
install script (install_psql_U2404_v1-movedir.sh).

------------------------------------------------------------------
The 'trap' line is placed near the top of the script, right after set -euo pipefail.

It sets up a trap for the ERR signal, which is triggered whenever a command
returns a non-zero exit status (i.e., an error occurs).
When an error happens, the trap calls the error_handler function, passing it:
- The exit code ($?)
- The current line number ($LINENO)
- The Bash line number array ($BASH_LINENO)
- The last command executed ("$BASH_COMMAND")
- The function call stack (using FUNCNAME)

This provides detailed error reporting and debugging information whenever
any error occurs in the script, making troubleshooting much easier.
------------------------------------------------------------------

WHAT THIS SCRIPT UNDOES (in reverse install order):
  1. Stops and disables the PostgreSQL systemd service
  2. Removes the symlink at PSQL_DEFAULT_DATA_DIR
  3. Restores PSQL_DEFAULT_DATA_DIR_ORIG back to PSQL_DEFAULT_DATA_DIR (if found)
  4. Optionally removes the custom data directory NEW_DATA_DIR (--purge-data flag)
  5. Removes the log directory (/var/log/postgres)
  6. Removes the lock directory (/var/run/postgresql)
  7. Purges postgresql packages via apt-get
  8. Removes the PGDG apt source list (/etc/apt/sources.list.d/pgdg.list)
  9. Removes the GPG keyring (/usr/share/keyrings/postgresql-keyring.gpg)
 10. Verifies the system is clean

Usage: ./uninstall_psql_U2404_v1-movedir.sh [version] [--purge-data]
Example: ./uninstall_psql_U2404_v1-movedir.sh 16
Example: ./uninstall_psql_U2404_v1-movedir.sh 16 --purge-data

WARNING: --purge-data will PERMANENTLY DELETE /db/mypg<version>.
         Your database data will be UNRECOVERABLE. Use with caution.

Revised: Sat 2026Apr04
Author: devesplabs
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
COMMENT

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

# ── Load shared PostgreSQL configuration ────────────────────────────
# Resolved relative to THIS script's location (not the caller's pwd).
# Source the config file if present — sets PG_VERSION and any future vars.
PG_CONFIG_FILE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/pg-config.env"
if [[ -f "${PG_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    . "${PG_CONFIG_FILE}"
fi
unset PG_CONFIG_FILE

# Default PostgreSQL version (must match what was used during install)
# Priority: CLI arg > env var (PG_VERSION from pg-config.env or shell) > built-in fallback
PG_VERSION="${1:-${PG_VERSION:-16}}"
# ────────────────────────────────────────────────────────────────────

# Flag: pass --purge-data as second argument to also delete the custom data dir
PURGE_DATA=false
for arg in "$@"; do
    if [[ "$arg" == "--purge-data" ]]; then
        PURGE_DATA=true
    fi
done

# Directories — must mirror install script exactly
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
# Note: lsb_release is deprecated and not installed by default in Ubuntu 24.04.
# Use /etc/os-release instead (sourced per POSIX/LSB standards).
check_operating_system() {
    echo
    echo "----------------------------------------"
    echo " Checking Operating System "
    echo "----------------------------------------"
    echo
    local os_id os_version
    os_id=$(. /etc/os-release && echo "$ID")
    os_version=$(. /etc/os-release && echo "$VERSION_ID")

    if [[ "$os_id" != "ubuntu" ]]; then
        log_error "This script is designed to run on Ubuntu"
        exit 1
    fi

    if [[ "$os_version" != "24.04" ]]; then
        log_warning "This script is optimized for Ubuntu 24.04 (detected: ${os_version})"
    fi
}

# Safety confirmation before any destructive action
confirm_uninstall() {
    echo
    echo "========================================================"
    echo -e "  ${RED}WARNING: PostgreSQL Uninstallation${NC}"
    echo "========================================================"
    echo
    echo "  This will PERMANENTLY remove:"
    echo "    - PostgreSQL ${PG_VERSION} packages (purge)"
    echo "    - PGDG apt repository and GPG keyring"
    echo "    - Log directory  : ${LOG_DIR}"
    echo "    - Lock directory : ${LOCK_DIR}"
    echo "    - Symlink        : ${PSQL_DEFAULT_DATA_DIR}"
    if [[ "${PURGE_DATA}" == "true" ]]; then
        echo -e "    - ${RED}DATA DIRECTORY  : ${NEW_DATA_DIR}  <-- ALL DATA WILL BE LOST${NC}"
    else
        echo "    - Data directory : ${NEW_DATA_DIR} will be PRESERVED (use --purge-data to delete)"
    fi
    echo
    echo -n "  Type 'yes' to confirm uninstallation: "
    read -r confirmation
    echo
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Uninstallation cancelled by user."
        exit 0
    fi
}

# STEP 1: Stop and disable the PostgreSQL service
stop_postgresql_service() {
    echo
    echo "----------------------------------------"
    echo " Stopping PostgreSQL Service "
    echo "----------------------------------------"
    echo
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        log_info "Stopping PostgreSQL service..."
        systemctl stop postgresql
        log_success "PostgreSQL service stopped"
    else
        log_warning "PostgreSQL service is not running (skipping stop)"
    fi

    if systemctl is-enabled postgresql &>/dev/null 2>&1; then
        log_info "Disabling PostgreSQL service..."
        systemctl disable postgresql
        log_success "PostgreSQL service disabled"
    else
        log_warning "PostgreSQL service is not enabled (skipping disable)"
    fi
}

# STEP 2: Restore the data directory (reverse of setup_data_directory)
# Install did:
#   1. mkdir NEW_DATA_DIR
#   2. cp -a PSQL_DEFAULT_DATA_DIR/. NEW_DATA_DIR/
#   3. mv PSQL_DEFAULT_DATA_DIR  --> PSQL_DEFAULT_DATA_DIR_ORIG
#   4. ln -sf NEW_DATA_DIR PSQL_DEFAULT_DATA_DIR
#
# Uninstall reverses:
#   1. Remove the symlink at PSQL_DEFAULT_DATA_DIR
#   2. Restore PSQL_DEFAULT_DATA_DIR_ORIG --> PSQL_DEFAULT_DATA_DIR (if exists)
#   3. Optionally remove NEW_DATA_DIR (only with --purge-data)
restore_data_directory() {
    echo
    echo "----------------------------------------"
    echo " Restoring Data Directory "
    echo "----------------------------------------"
    echo

    # Remove the symlink
    if [[ -L "${PSQL_DEFAULT_DATA_DIR}" ]]; then
        log_info "Removing symlink: ${PSQL_DEFAULT_DATA_DIR} -> $(readlink ${PSQL_DEFAULT_DATA_DIR})"
        rm -f "${PSQL_DEFAULT_DATA_DIR}"
        log_success "Symlink removed"
    else
        log_warning "Symlink ${PSQL_DEFAULT_DATA_DIR} not found (may have already been removed)"
    fi

    # Restore the _ORIG backup if it exists
    if [[ -d "${PSQL_DEFAULT_DATA_DIR}_ORIG" ]]; then
        log_info "Restoring original data directory: ${PSQL_DEFAULT_DATA_DIR}_ORIG -> ${PSQL_DEFAULT_DATA_DIR}"
        mv "${PSQL_DEFAULT_DATA_DIR}_ORIG" "${PSQL_DEFAULT_DATA_DIR}"
        log_success "Original data directory restored"
    else
        log_warning "Original backup ${PSQL_DEFAULT_DATA_DIR}_ORIG not found (skipping restore)"
    fi

    # Optionally purge the custom data directory
    if [[ "${PURGE_DATA}" == "true" ]]; then
        if [[ -d "${NEW_DATA_DIR}" ]]; then
            log_warning "Purging custom data directory: ${NEW_DATA_DIR}"
            rm -rf "${NEW_DATA_DIR}"
            log_success "Custom data directory removed: ${NEW_DATA_DIR}"
        else
            log_warning "Custom data directory ${NEW_DATA_DIR} not found (already removed)"
        fi
    else
        if [[ -d "${NEW_DATA_DIR}" ]]; then
            log_info "Preserving custom data directory: ${NEW_DATA_DIR}"
            log_info "To remove it manually: rm -rf ${NEW_DATA_DIR}"
        fi
    fi
}

# STEP 3: Remove log directory
remove_log_directory() {
    echo
    echo "----------------------------------------"
    echo " Removing Log Directory "
    echo "----------------------------------------"
    echo
    if [[ -d "${LOG_DIR}" ]]; then
        log_info "Removing log directory: ${LOG_DIR}"
        rm -rf "${LOG_DIR}"
        log_success "Log directory removed"
    else
        log_warning "Log directory ${LOG_DIR} not found (skipping)"
    fi
}

# STEP 4: Remove lock directory
remove_lock_directory() {
    echo
    echo "----------------------------------------"
    echo " Removing Lock Directory "
    echo "----------------------------------------"
    echo
    if [[ -d "${LOCK_DIR}" ]]; then
        log_info "Removing lock directory: ${LOCK_DIR}"
        rm -rf "${LOCK_DIR}"
        log_success "Lock directory removed"
    else
        log_warning "Lock directory ${LOCK_DIR} not found (skipping)"
    fi
}

# STEP 5: Purge PostgreSQL packages
uninstall_postgresql() {
    echo
    echo "----------------------------------------"
    echo " Purging PostgreSQL ${PG_VERSION} Packages "
    echo "----------------------------------------"
    echo
    log_info "Purging PostgreSQL ${PG_VERSION} packages..."

    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        postgresql-${PG_VERSION} \
        postgresql-contrib-${PG_VERSION} \
        python3-psycopg2 \
        2>/dev/null || log_warning "Some packages were not installed — continuing"

    log_info "Running autoremove to clean up dependencies..."
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

    log_info "Cleaning apt cache..."
    DEBIAN_FRONTEND=noninteractive apt-get clean

    log_success "PostgreSQL packages purged"
}

# STEP 6: Remove PGDG repository and GPG keyring
remove_postgresql_repository() {
    echo
    echo "----------------------------------------"
    echo " Removing PGDG Repository & GPG Keyring "
    echo "----------------------------------------"
    echo

    # Remove apt source list
    if [[ -f /etc/apt/sources.list.d/pgdg.list ]]; then
        log_info "Removing PGDG apt source list..."
        rm -f /etc/apt/sources.list.d/pgdg.list
        log_success "PGDG source list removed"
    else
        log_warning "PGDG source list not found (skipping)"
    fi

    # Remove GPG keyring
    if [[ -f /usr/share/keyrings/postgresql-keyring.gpg ]]; then
        log_info "Removing PostgreSQL GPG keyring..."
        rm -f /usr/share/keyrings/postgresql-keyring.gpg
        log_success "GPG keyring removed"
    else
        log_warning "PostgreSQL GPG keyring not found (skipping)"
    fi

    log_info "Updating package lists after repository removal..."
    DEBIAN_FRONTEND=noninteractive apt-get update
}

# STEP 7: Verify uninstallation is clean
verify_uninstall() {
    echo
    echo "----------------------------------------"
    echo " Verifying Uninstallation "
    echo "----------------------------------------"
    echo
    log_info "Verifying PostgreSQL has been removed..."

    local issues=0

    # Check PostgreSQL binary is gone
    if command -v psql &>/dev/null; then
        log_warning "psql binary still found at: $(command -v psql)"
        ((issues++)) || true
    else
        log_success "psql binary: removed"
    fi

    # Check service is gone
    if systemctl list-units --type=service 2>/dev/null | grep -q "postgresql"; then
        log_warning "PostgreSQL systemd service still present"
        ((issues++)) || true
    else
        log_success "PostgreSQL service: removed"
    fi

    # Check PGDG source list is gone
    if [[ -f /etc/apt/sources.list.d/pgdg.list ]]; then
        log_warning "PGDG source list still present: /etc/apt/sources.list.d/pgdg.list"
        ((issues++)) || true
    else
        log_success "PGDG source list: removed"
    fi

    # Check GPG keyring is gone
    if [[ -f /usr/share/keyrings/postgresql-keyring.gpg ]]; then
        log_warning "PostgreSQL GPG keyring still present"
        ((issues++)) || true
    else
        log_success "PostgreSQL GPG keyring: removed"
    fi

    # Check symlink is gone
    if [[ -L "${PSQL_DEFAULT_DATA_DIR}" ]]; then
        log_warning "Symlink still present: ${PSQL_DEFAULT_DATA_DIR}"
        ((issues++)) || true
    else
        log_success "Data directory symlink: removed"
    fi

    # Check log directory is gone
    if [[ -d "${LOG_DIR}" ]]; then
        log_warning "Log directory still present: ${LOG_DIR}"
        ((issues++)) || true
    else
        log_success "Log directory: removed"
    fi

    # Report data directory status (not a failure — may be intentionally preserved)
    if [[ -d "${NEW_DATA_DIR}" ]]; then
        log_info "Custom data directory preserved: ${NEW_DATA_DIR}"
        log_info "  To remove: rm -rf ${NEW_DATA_DIR}"
    else
        log_success "Custom data directory: removed"
    fi

    echo
    if [[ ${issues} -eq 0 ]]; then
        log_success "Uninstallation verification complete — system is clean"
        return 0
    else
        log_warning "Uninstallation complete with ${issues} warning(s) — review above"
        return 1
    fi
}

# Check how much time passed between start and end
calculate_time_difference() {
    log_info "Calculating uninstallation time difference..."
    local start_time=$1
    local end_time=$2

    start_seconds=$(date -d "$start_time" +%s)
    end_seconds=$(date -d "$end_time  " +%s)
    diff_seconds=$((end_seconds - start_seconds))

    readable_time_human=$(date -u -d @"$diff_seconds" +"%H:%M:%S")
    log_info "Total uninstallation time: $readable_time_human (HH:MM:SS)"
    echo
    echo "Start time:     $start_time"
    echo "End time:       $end_time"
    echo "Total duration: $diff_seconds seconds"
}

# Main function
main() {
    local start_time
    start_time=$(date +"%Y-%m-%d %H:%M:%S")

    echo
    echo "----------------------------------------"
    echo " PostgreSQL Uninstallation Script "
    echo "----------------------------------------"
    echo
    log_info "Starting PostgreSQL ${PG_VERSION} uninstallation on Ubuntu 24.04 (Noble Numbat)..."
    if [[ "${PURGE_DATA}" == "true" ]]; then
        log_warning "--purge-data flag set: custom data directory WILL be deleted"
    fi

    check_root
    check_operating_system

    # Check if PostgreSQL is actually installed before proceeding
    if ! command -v psql &>/dev/null && ! dpkg -l "postgresql-${PG_VERSION}" &>/dev/null 2>&1; then
        log_info "PostgreSQL ${PG_VERSION} does not appear to be installed. Nothing to do."
        exit 0
    fi

    confirm_uninstall

    # Reverse order of install steps
    stop_postgresql_service
    restore_data_directory
    remove_log_directory
    remove_lock_directory
    uninstall_postgresql
    remove_postgresql_repository

    if verify_uninstall; then
        log_success "PostgreSQL ${PG_VERSION} uninstallation completed successfully"
    else
        log_warning "PostgreSQL ${PG_VERSION} uninstallation completed with warnings"
    fi

    local end_time
    end_time=$(date +"%Y-%m-%d %H:%M:%S")

    calculate_time_difference "$start_time" "$end_time"
}

# Run main function
main "$@"
