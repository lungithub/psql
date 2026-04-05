#!/bin/bash
: <<'COMMENT'
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

PURPOSE: set up the environment for the postgres user

This script sets up the environment for the postgres user, including
creating .bashrc, .bash_profile, and .aliasrc files with appropriate content
and permissions.

CALLED BY: install_psql_U2404_v1-movedir.sh (configure_postgres_environment step)

ARGUMENTS PASSED BY CALLER:
  $1  PGHOME      — postgres home directory  (default: /var/lib/postgresql)
  $2  PG_VERSION  — PostgreSQL major version (default: 13)

  Do NOT run this script directly unless you pass both arguments explicitly:
    sudo bash psql_postgres_environment.sh /var/lib/postgresql 16

  PG_VERSION is NOT sourced from pg-config.env here — the calling install
  script resolves PG_VERSION (via pg-config.env / env var / CLI arg) and
  passes it down as $2. This keeps version resolution in a single place.

Date: Sat 2023Jan14 13:17:51 PST
Revised: Sat 2026Apr04 12:00:00 PST
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
COMMENT



set -euo pipefail  # Exit on error, undefined vars, and pipeline errors

# Target PostgreSQL OS user — override via env var if needed
PG_USER="${PG_USER:-postgres}"

#
# Default PostgreSQL version
PGHOME="${1:-/var/lib/postgresql}"
PG_VERSION="${2:-13}"

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

check_settings() {
    if [[ -z "$PGHOME" || ! -d "$PGHOME" ]]; then
        log_error "PGHOME is not set correctly. Current value: '$PGHOME'"
        exit 1
    fi
    if [[ -z "$PG_VERSION" ]]; then
        log_error "PG_VERSION is not set."
        exit 1
    fi
    echo "PGHOME is set to ......: '$PGHOME'"
    echo "PG_VERSION is set to ..: '$PG_VERSION'"

}

# Function to create .bashrc for postgres user
create_bashrc() {
    if [[ ! -f "$PGHOME/.bashrc" ]]; then
        log_info "Creating $PGHOME/.bashrc for postgres user."
        touch "$PGHOME/.bashrc"
        chown "${PG_USER}:${PG_USER}" "$PGHOME/.bashrc"
    fi
    # Add custom PS1 prompt if not already present
    if ! grep -q 'PS1=' "$PGHOME/.bashrc"; then
        log_info "Adding custom PS1 prompt to $PGHOME/.bashrc"
        cat <<'EOF' >> "$PGHOME/.bashrc"
PS1='
\[\e[35m\]$(/bin/date +%a" "%Y%b%d" "%H:%M:%S" "%Z) \[\e[m\]
\[\e[1;32m\]\u@devesp \[\e[m\]
\[\e[1;34m\]\w \[\e[m\]
\[\e[1;33m\]hist:\! \[\e[m\]\[\e[0;31m\]->\[\e[m\] '
EOF
        chown "${PG_USER}:${PG_USER}" "$PGHOME/.bashrc"
    fi
}

# Function to create .bash_profile for postgres user
create_bash_profile() {
    if [[ ! -f "$PGHOME/.bash_profile" ]]; then
        log_info "Creating $PGHOME/.bash_profile for postgres user."
        echo '[ -f ~/.bashrc ] && . ~/.bashrc' > "$PGHOME/.bash_profile"
        chown "${PG_USER}:${PG_USER}" "$PGHOME/.bash_profile"
    fi
}

# Function to create .aliasrc for postgres user
create_aliasrc() {
    if [[ ! -f "$PGHOME/.aliasrc" ]]; then
        log_info "Creating $PGHOME/.aliasrc for postgres user."
        touch "$PGHOME/.aliasrc"
        chown "${PG_USER}:${PG_USER}" "$PGHOME/.aliasrc"
    fi
}

# Function to add aliases to .aliasrc
# Uses PG_VERSION variable (passed as $2 from caller) so aliases target the
# correct service unit — e.g. postgresql@16-main instead of hardcoded @13.
add_postgres_aliases() {
    local pg_service="postgresql@${PG_VERSION}-main.service"
    if ! grep -q "systemctl start ${pg_service}" "$PGHOME/.aliasrc"; then
        log_info "Adding pgstart alias to .aliasrc (service: ${pg_service})"
        echo "alias pgstart='sudo systemctl start ${pg_service} --no-pager'" >> "$PGHOME/.aliasrc"
    fi
    if ! grep -q "systemctl stop ${pg_service}" "$PGHOME/.aliasrc"; then
        log_info "Adding pgstop alias to .aliasrc (service: ${pg_service})"
        echo "alias pgstop='sudo systemctl stop ${pg_service} --no-pager'" >> "$PGHOME/.aliasrc"
    fi
    if ! grep -q "systemctl status ${pg_service}" "$PGHOME/.aliasrc"; then
        log_info "Adding pgstatus alias to .aliasrc (service: ${pg_service})"
        echo "alias pgstatus='sudo systemctl status ${pg_service} --no-pager'" >> "$PGHOME/.aliasrc"
    fi
    chown "${PG_USER}:${PG_USER}" "$PGHOME/.aliasrc"
}

# Function to ensure .aliasrc is sourced from .bashrc
ensure_aliasrc_sourced() {
    if ! grep -q 'aliasrc' "$PGHOME/.bashrc"; then
        log_info "Adding .aliasrc sourcing to .bashrc"
        echo "[ -f ~/.aliasrc ] && . ~/.aliasrc" >> "$PGHOME/.bashrc"
    fi
    chown "${PG_USER}:${PG_USER}" "$PGHOME/.bashrc"
}

# Main logic
if [[ -z "$PGHOME" || ! -d "$PGHOME" ]]; then
    log_warning "Could not determine postgres home directory. Skipping shell file setup."
    exit 1
fi

check_settings
create_bashrc
create_bash_profile
create_aliasrc
add_postgres_aliases
ensure_aliasrc_sourced
