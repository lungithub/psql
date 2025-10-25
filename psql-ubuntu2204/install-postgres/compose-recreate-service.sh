#!/bin/bash
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#  PURPOSE:  Script to recreate a Docker Compose service.
#
# ------------------------------------------------------------------
#
# Usage: 
#   ./compose-recreate-service.sh <service_name> 
# Example:  
#   ./compose-recreate-service.sh pgnode1
# Where pgnode1 is the name of the service defined in docker-compose.yml
#
# Caveats:
# You get "$1: unbound variable" error because we are using set -u (treat unset 
# variables as an error), and your script's main() function expects a positional 
# argument ($1). This error would occure when not passing any arguments when 
# running the script without checking for the number of arguments.
#
# ------------------------------------------------------------------
# 
# Reference:
# https://unix.stackexchange.com/questions/463034/bash-throws-error-line-8-1-unbound-variable
#
# Date: Sat 2025Oct25 10:42:22 PDT
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

# display help
usage() {
    echo 
    echo "Usage: $0 <service_name>"
    echo "Example: $0 pgnode1"
    echo
    exit 1
}

compose_recreate_service() {
    local service_name=$1

    log_info "Recreating Docker Compose service: $service_name"

    docker compose stop "$service_name" 
    if [[ $? -ne 0 ]]; then
        log_warning "Failed to stop service $service_name"
    fi
    docker compose rm -f "$service_name" 
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to remove service $service_name"
        fi
    docker compose up -d "$service_name" 
    if [[ $? -ne 0 ]]; then
        log_error "Failed to start service $service_name"
        FAILED=true
        error_handler 1 $LINENO $BASH_LINENO "docker compose up -d $service_name" "compose_recreate_service"
    fi

    if [[ "${FAILED:-false}" == true ]]; then
        log_error "Service $service_name recreation encountered errors."
        exit 1
    else
        log_success "Service $service_name recreated successfully."
    fi
}

# Function to check existing settings
# This function calculates the time difference between two timestamps.
# The calulation accounts for differences in date command syntax between Linux and macOS.
calculate_time_difference() {
    log_info "Calculating installation time difference..."
    local start_time="$1"
    local end_time="$2"

    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS/BSD date
        start_seconds=$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" "+%s")
        end_seconds=$(date -j -f "%Y-%m-%d %H:%M:%S" "$end_time" "+%s")
    else
        # Linux/GNU date
        start_seconds=$(date -d "$start_time" "+%s")
        end_seconds=$(date -d "$end_time" "+%s")
    fi

    diff_seconds=$((end_seconds - start_seconds))
    readable_time_human=$(printf '%02d:%02d:%02d' $((diff_seconds/3600)) $(((diff_seconds%3600)/60)) $((diff_seconds%60)) )

    log_info "Total installation time: $readable_time_human (HH:MM:SS)"
    echo
    echo "Start time: $start_time"
    echo "End time:   $end_time"
    echo "Total duration: $diff_seconds seconds"
}

# Main function
# Checks for a required service name argument at the start of main(). 
# If no argument is provided, it prints a usage message and exits, preventing the "unbound variable" error.
main() {
    if [[ $# -lt 1 ]]; then
        echo
        log_error "No service name provided."
        usage
        exit 1
    fi

    local container_name=$1
    local start_time=$(date +"%Y-%m-%d %H:%M:%S")

    log_info "Starting recreation of Docker Compose service: $container_name"
    compose_recreate_service "$container_name"
    sleep 5

    local end_time=$(date +"%Y-%m-%d %H:%M:%S")
    calculate_time_difference "$start_time" "$end_time"
}

# Run main function
main "$@"