#!/usr/bin/env bash
# Provides a simply check script that can be used to monitor services of users from root.
# Takes two arguments, the first being the username, the second being the full service name (e.g "nginx.service").
# Usage:
#   ./script.sh <username> <service_name>

# Helper to run systemctl commands as the specified user.
systemd_as_user() {
    ARGS=("$@")
    local current_user
    current_user=$(id -un)

    if [ "$current_user" = "$USERNAME" ]; then
        systemctl --user "${ARGS[@]}"
    else
        systemctl --user --machine="${USERNAME}@" "${ARGS[@]}"
    fi
}

parse_args() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 <username> <service_name>"
        exit 1
    fi

    USERNAME="$1"
    SERVICE_NAME="$2"
}

validate_commands() {
    COMMANDS=("id" "systemctl")
    MISSING_COMMANDS=()
    for cmd in "${COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            MISSING_COMMANDS+=("$cmd")
        fi
    done
    if [ ${#MISSING_COMMANDS[@]} -ne 0 ]; then
        echo "Error: The following required commands are missing: ${MISSING_COMMANDS[*]}"
        echo "Please install them and try again."
        exit 1
    fi
}

validate_user() {
    if ! id "$USERNAME" &>/dev/null; then
        echo "Error: User '$USERNAME' does not exist."
        exit 1
    fi
}

validate_unit() {
    if ! systemd_as_user list-units --all --no-legend | grep -qw "$SERVICE_NAME"; then
        echo "Error: Service '$SERVICE_NAME' does not exist for user '$USERNAME'."
        exit 1
    fi
}

check_service_status() {
    local status
    status=$(systemd_as_user is-active "$SERVICE_NAME")
    if [ "$status" != "active" ]; then
        echo "Error: Service '$SERVICE_NAME' is not active for user '$USERNAME'."
        exit 1
    fi

    local show_output
    show_output=$(systemd_as_user show -p ActiveEnterTimestamp,NRestarts,StatusText,StatusErrno "$SERVICE_NAME")

    local last_restart
    last_restart=$(echo "$show_output" | grep "^ActiveEnterTimestamp=" | cut -d'=' -f2)
    if [ -n "$last_restart" ]; then
        local last_restart_epoch
        last_restart_epoch=$(date -d "$last_restart" +%s)
        local current_epoch
        current_epoch=$(date +%s)
        local diff=$((current_epoch - last_restart_epoch))
        if [ $diff -lt 300 ]; then
            echo "Warning: Service '$SERVICE_NAME' was restarted recently (within the last 5 minutes)."
        fi
    fi

    local restart_count
    restart_count=$(echo "$show_output" | grep "^NRestarts=" | cut -d'=' -f2)
    if [ -n "$restart_count" ] && [ "$restart_count" -gt 0 ]; then
        echo "Warning: Service '$SERVICE_NAME' has restarted $restart_count times recently."
    fi

    local status_text
    status_text=$(echo "$show_output" | grep "^StatusText=" | cut -d'=' -f2)
    local status_errno
    status_errno=$(echo "$show_output" | grep "^StatusErrno=" | cut -d'=' -f2)
    if [ -n "$status_errno" ] && [ "$status_errno" -ne 0 ]; then
        echo "Warning: Service '$SERVICE_NAME' has a non-zero status errno ($status_errno). Status text: $status_text"
    fi

    echo "Service '$SERVICE_NAME' is active and running for user '$USERNAME'."
}

parse_args "$@"
validate_commands
validate_user
validate_unit
check_service_status
