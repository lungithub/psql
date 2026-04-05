#!/bin/bash
: <<'COMMENT'
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
PostgreSQL Installation Script for Ubuntu 24.04
This script installs and configures PostgreSQL with proper directory structure
and permissions.

------------------------------------------------------------------
The 'trap' line is placed near the top of the script, right after set -euo pipefail.

It sets up a trap for the ERR signal, which is triggered whenever a command returns a non-zero exit status (i.e., an error occurs).
When an error happens, the trap calls the error_handler function, passing it:
- The exit code ($?)
- The current line number ($LINENO)
- The Bash line number array ($BASH_LINENO)
- The last command executed ("$BASH_COMMAND")
- The function call stack (using FUNCNAME)

This provides detailed error reporting and debugging information whenever any error occurs in the script, making troubleshooting much easier.
------------------------------------------------------------------

Usage: ./install_psql_U2404_v1-movedir.sh [version|--help]
Run with -h or --help for full usage details.

Date: Mon 2025Jun16
Date Modified: Sat 2025Oct18 14:19:03 PDT -- complete rewrite with movedir functionality
- add logging functions
- add error handling with trap
- add OS check
- improve PostgreSQL repository key handling
Date Modified: Sat 2026Apr04 -- ported to Ubuntu 24.04 (Noble Numbat)
- replace lsb_release with /etc/os-release (lsb_release deprecated in 24.04)
- update default PostgreSQL version to 16
- update all psql-ubuntu2204 paths to psql-ubuntu2404

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

# Usage / help
usage() {
    echo
    echo -e "${BLUE}NAME${NC}"
    echo "    install_psql_U2404_v1-movedir.sh"
    echo "    PostgreSQL installation script for Ubuntu 24.04 (Noble Numbat)"
    echo
    echo -e "${BLUE}SYNOPSIS${NC}"
    echo "    sudo ./install_psql_U2404_v1-movedir.sh [VERSION]"
    echo "    sudo ./install_psql_U2404_v1-movedir.sh [-h | --help]"
    echo
    echo -e "${BLUE}DESCRIPTION${NC}"
    echo "    Installs and configures a PostgreSQL server on Ubuntu 24.04."
    echo "    The data directory is moved from its default location to a"
    echo "    custom path and a symlink is created in its place, allowing"
    echo "    the data to reside on a separate disk or partition."
    echo
    echo -e "${BLUE}ARGUMENTS${NC}"
    echo "    VERSION     PostgreSQL major version to install."
    echo "                Supported: 13 | 14 | 15 | 16 | 17"
    echo "                Default  : read from pg-config.env, fallback to 16"
    echo
    echo -e "${BLUE}VERSION RESOLUTION ORDER${NC} (highest → lowest priority)"
    echo "    1. CLI argument           ./install_psql_U2404_v1-movedir.sh 17"
    echo "    2. Shell env variable     export PG_VERSION=17"
    echo "    3. pg-config.env file     PG_VERSION=16     ← team default"
    echo "    4. Built-in fallback      16"
    echo
    echo -e "${BLUE}CONFIG FILE${NC}"
    echo "    pg-config.env — sits alongside this script."
    echo "    Edit PG_VERSION there to change the default for all scripts."
    echo
    echo -e "${BLUE}WHAT THIS SCRIPT DOES${NC}"
    echo "    1. Adds the official PGDG apt repository and GPG key"
    echo "    2. Installs postgresql-<VERSION> and postgresql-contrib-<VERSION>"
    echo "    3. Moves the data directory to /db/mypg<VERSION>"
    echo "    4. Creates a symlink: /var/lib/postgresql/<VERSION>/main -> /db/mypg<VERSION>"
    echo "    5. Creates log dir  : /var/log/postgres"
    echo "    6. Creates lock dir : /var/run/postgresql"
    echo "    7. Enables and starts the postgresql systemd service"
    echo
    echo -e "${BLUE}EXAMPLES${NC}"
    echo "    # Install default version (from pg-config.env)"
    echo "    sudo ./install_psql_U2404_v1-movedir.sh"
    echo
    echo "    # Install PostgreSQL 16 explicitly"
    echo "    sudo ./install_psql_U2404_v1-movedir.sh 16"
    echo
    echo "    # Install PostgreSQL 17 (one-off override)"
    echo "    sudo ./install_psql_U2404_v1-movedir.sh 17"
    echo
    echo "    # Install using environment variable override"
    echo "    export PG_VERSION=15 && sudo ./install_psql_U2404_v1-movedir.sh"
    echo
    echo -e "${BLUE}SEE ALSO${NC}"
    echo "    uninstall_psql_U2404_v1-movedir.sh   Reverses this installation"
    echo "    pg-config.env                         Shared version configuration"
    echo
}

# Show usage if help flag is passed (checked before trap and PG_VERSION assignment)
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

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
# ── Load shared PostgreSQL configuration ────────────────────────────
# Resolved relative to THIS script's location (not the caller's pwd).
# Source the config file if present — sets PG_VERSION and any future vars.
PG_CONFIG_FILE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/pg-config.env"
if [[ -f "${PG_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    . "${PG_CONFIG_FILE}"
fi
unset PG_CONFIG_FILE

# Default PostgreSQL version
# Priority: CLI arg > env var (PG_VERSION from pg-config.env or shell) > built-in fallback
PG_VERSION="${1:-${PG_VERSION:-16}}"
# ────────────────────────────────────────────────────────────────────

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


# Installation confirmation banner
# Displays a summary of what will be installed and where, then prompts
# the user to confirm before any packages are installed or dirs are created.
confirm_install() {
    local os_version
    os_version=$(. /etc/os-release && echo "$ID $VERSION_ID ($VERSION_CODENAME)")

    echo
    echo "========================================================"
    echo -e "  ${BLUE}PostgreSQL Installation Summary${NC}"
    echo "========================================================"
    echo
    echo "  PostgreSQL version : ${PG_VERSION}"
    echo "  Operating system   : ${os_version}"
    echo "  PGDG repository    : https://apt.postgresql.org/pub/repos/apt"
    echo
    echo "  Directories that will be created:"
    echo "    Data directory   : ${NEW_DATA_DIR}"
    echo "    Log directory    : ${LOG_DIR}"
    echo "    Lock directory   : ${LOCK_DIR}"
    echo
    echo "  Symlink that will be created:"
    echo "    ${PSQL_DEFAULT_DATA_DIR} -> ${NEW_DATA_DIR}"
    echo
    echo "  Packages to install:"
    echo "    postgresql-${PG_VERSION}"
    echo "    postgresql-contrib-${PG_VERSION}"
    echo "    python3-psycopg2"
    echo
    echo "  Version source     : pg-config.env (override with CLI arg or env var)"
    echo
    echo "========================================================"
    echo
    echo -n "  Type 'yes' to proceed with installation: "
    read -r confirmation
    echo
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Installation cancelled by user."
        exit 0
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
    
    # GPG keyring setup for Ubuntu 24.04
    # - apt-key is fully REMOVED in Ubuntu 24.04 (not just deprecated); use signed-by instead
    # - gpg --dearmor creates files with 600 (root-only) permissions by default
    # - Ubuntu 24.04 runs apt operations as the '_apt' user (dropped privileges),
    #   so the keyring MUST be world-readable (644) or apt-get update will fail
    # Overwrite keyring file without prompt
    if [[ -f /usr/share/keyrings/postgresql-keyring.gpg ]]; then
        rm -f /usr/share/keyrings/postgresql-keyring.gpg
    fi
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
    chmod 644 /usr/share/keyrings/postgresql-keyring.gpg  # Required: _apt user must be able to read this

    # Use /etc/os-release instead of lsb_release (deprecated in Ubuntu 24.04)
    local codename
    codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    # Use https:// — PGDG prefers it and Ubuntu 24.04 apt transport defaults favor it
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" > /etc/apt/sources.list.d/pgdg.list

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
# Resolves companion script path relative to THIS script's location,
# not a hardcoded /hostdata path which may not exist in all environments.
copy_management_files() {
    echo
    echo "----------------------------------------"
    echo " Copying PostgreSQL Management Files "
    echo "----------------------------------------"
    echo
    local script_dir
    script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    local mgmt_script="${script_dir}/copy_psql_management_files.sh"

    if [[ -f "${mgmt_script}" ]]; then
        log_info "Copying management files..."
        log_info "Running: ${mgmt_script}"
        bash "${mgmt_script}" || {
            log_warning "Failed to copy management files"
            return 1
        }
    else
        log_warning "Management files script not found: ${mgmt_script}"
        return 1
    fi
}

# Configure postgres sudo access
# Resolves the companion script path relative to THIS script's location,
# not a hardcoded /hostdata path which may not exist in all environments.
configure_postgres_sudo() {
    echo
    echo "----------------------------------------"
    echo " Configuring PostgreSQL Sudo Environment "
    echo "----------------------------------------"
    echo
    local script_dir
    script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    local sudo_script="${script_dir}/psql_postgres_sudo.sh"

    if [[ -f "${sudo_script}" ]]; then
        log_info "Configuring postgres sudo environment..."
        log_info "Running: ${sudo_script}"
        bash "${sudo_script}" || {
            log_warning "Failed to configure postgres sudo environment"
            return 1
        }
    else
        log_warning "Sudo configuration script not found: ${sudo_script}"
        return 1
    fi
}

# Configure postgres shell environment (.bashrc, .bash_profile, aliases)
# Resolves companion script relative to THIS script's location.
# Passes PGHOME and PG_VERSION explicitly so the child script uses the
# correct version — not its own hardcoded default of 13.
configure_postgres_environment() {
    echo
    echo "----------------------------------------"
    echo " Configuring PostgreSQL Environment "
    echo "----------------------------------------"
    echo
    local script_dir
    script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    local env_script="${script_dir}/psql_postgres_environment.sh"

    if [[ -f "${env_script}" ]]; then
        log_info "Configuring postgres environment for PG version ${PG_VERSION}..."
        log_info "Running: ${env_script} /var/lib/postgresql ${PG_VERSION}"
        # Pass PGHOME ($1) and PG_VERSION ($2) explicitly
        bash "${env_script}" /var/lib/postgresql "${PG_VERSION}" || {
            log_warning "Failed to configure postgres environment"
            return 1
        }
    else
        log_warning "Environment configuration script not found: ${env_script}"
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
    log_info "Starting PostgreSQL ${PG_VERSION} installation on Ubuntu 24.04 (Noble Numbat)..."
    
    check_root
    check_operating_system

    if which psql > /dev/null; then
        log_info "psql is already installed. Skipping installation."
        exit 0
    fi

    confirm_install

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

    local end_time=$(date +"%Y-%m-%d %H:%M:%S")

    calculate_time_difference "$start_time" "$end_time"

}

# Run main function
main "$@"
