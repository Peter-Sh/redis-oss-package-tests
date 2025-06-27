#!/bin/bash

# Redis Package Tests using shunit2
# This script tests Redis package installation and basic functionality

# Global variables for test control
should_skip=false
skip_reasons=()
REDIS_INSTALLED=

if [ -z "$VERBOSITY" ]; then
    VERBOSITY=1
fi

# Global variables for command execution
last_cmd_stdout=""
last_cmd_stderr=""
last_cmd_result=0

# Special output function with 4-space indent and gray color
test_output() {
    printf "\033[90m    %s\033[0m\n" "$*"
}

# Function to initialize test variables
setUp() {
    should_skip=false
    skip_reasons=()
    last_cmd_stdout=""
    last_cmd_stderr=""
    last_cmd_result=0
}

# Function to execute command from array and capture output
execute_command() {
    local cmd

    # Check if no arguments provided
    if [ $# -eq 0 ]; then
        # Check if cmd_array variable exists and is an array
        if declare -p cmd_array 2>/dev/null | grep -q "declare -a"; then
            # Use the existing cmd_array variable
            cmd=("${cmd_array[@]}")
        else
            echo "Error: No arguments provided and cmd_array variable not found or not an array" >&2
            return 1
        fi
    else
        cmd=("$@")
    fi

    # Create temporary files for stdout and stderr
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    # Execute command and capture output
    console_output 1 gray "Executing command: ${cmd[*]}"
    "${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
    last_cmd_result=$?

    # Read captured output
    last_cmd_stdout=$(cat "$stdout_file")
    last_cmd_stderr=$(cat "$stderr_file")

    if [ "$last_cmd_result" -ne 0 ]; then
        console_output 0 red "Command failed with exit code $last_cmd_result"
        console_output 0 red "Standard Output:"
        console_output 0 red "$last_cmd_stdout"
        console_output 0 red "Standard Error:"
        console_output 0 red "$last_cmd_stderr"
    fi

    # Clean up temporary files
    rm -f "$stdout_file" "$stderr_file"

    return $last_cmd_result
}

# Helper function to output multiline variables with color
console_output() {
    local verbosity_level="$1"
    local color="$2"
    local content="$3"
    local current_verbosity="${VERBOSITY:-0}"

    # Check if we should output based on verbosity level
    if [ "$current_verbosity" -ge "$verbosity_level" ]; then
        local color_code=""
        local reset_code="\033[0m"

        case "$color" in
            "gray"|"grey")
                color_code="\033[90m"
                ;;
            "white")
                color_code="\033[97m"
                ;;
            "red")
                color_code="\033[91m"
                ;;
            *)
                color_code="\033[0m"  # Default to no color
                ;;
        esac

        # Output each line with 4-space indent and color
        while IFS= read -r line || [ -n "$line" ]; do
            printf "${color_code}    %s${reset_code}\n" "$line"
        done <<< "$content"
    fi
}

# Helper function to print skip reasons
print_skip_reasons() {
    if [ ${#skip_reasons[@]} -gt 0 ]; then
        console_output 0 gray "Skip reasons:"
        for reason in "${skip_reasons[@]}"; do
            console_output 0 gray "  - $reason"
        done
    fi
}

# Helper function to check if OS ID matches requirement
require_id_like() {
    local required_id="$1"

    if [ -f /etc/os-release ]; then
        # Source the os-release file to get ID_LIKE and ID
        # shellcheck disable=SC1091
        . /etc/os-release

        # Check both ID and ID_LIKE
        if [[ "$ID" == *"$required_id"* ]] || [[ "$ID_LIKE" == *"$required_id"* ]]; then
            return 0
        else
            should_skip=true
            skip_reasons+=("OS ID requirement not met: required '$required_id', found ID='$ID' ID_LIKE='$ID_LIKE'")
            return 1
        fi
    else
        should_skip=true
        skip_reasons+=("Cannot determine OS ID: /etc/os-release not found")
        return 1
    fi
}

# Helper function to check if systemd is available
require_has_systemd() {
    if command -v systemctl >/dev/null 2>&1; then
        return 0
    else
        should_skip=true
        skip_reasons+=("systemd requirement not met: systemctl command not found")
        return 1
    fi
}

helper_install_redis() {
    ret=1
    if [ -n "$REDIS_RPM_INSTALL_FILES" ]; then
        helper_install_redis_from_rpm_files
        ret=$?
    else
        console_output 1 red "Didn't find a way to install Redis"
    fi

    return $ret
}

helper_install_redis_from_rpm_files() {
    if [ -n "$REDIS_INSTALLED" ]; then
        #shellcheck disable=SC2181
        if [ "$REDIS_INSTALLED" -ne 0 ]; then
            console_output 1 red "Redis installation failed previously, not attempting to install again" >&2
        fi
        # shellcheck disable=SC2086
        return $REDIS_INSTALLED
    fi
    execute_command sudo yum install -y $REDIS_RPM_INSTALL_FILES
    REDIS_INSTALLED=$last_cmd_result
    return $last_cmd_result
}

# Test function to check Redis RPM installation requirements
test_redis_rpm_install_files() {
    # Check if OS is RedHat-like
    require_id_like "rhel"

    # If re1quirements not met, skip the test
    if [ "$should_skip" = true ]; then
        startSkipping "$(print_skip_reasons)"
        return
    fi

    helper_install_redis
    ret=$?
    assertTrue "Failed to install Redis packages" $?

    execute_command getenforce
    console_output 1 gray "$last_cmd_stdout"
}

# Test function to check if Redis server starts successfully via systemd
test_systemd_start_redis() {
    if ! helper_install_redis; then
        return 1
    fi

    # Check requirements
    require_has_systemd

    # If requirements not met, skip the test
    if [ "$should_skip" = true ]; then
        startSkipping "$(print_skip_reasons)"
        return
    fi

    # Stop Redis if it's already running
    console_output 1 gray "Stopping Redis service if running..."
    execute_command sudo systemctl stop redis

    # Start Redis service
    console_output 1 gray "Starting Redis service..."
    execute_command sudo systemctl start redis
    assertTrue "Failed to start Redis service" "$last_cmd_result"
    if [ "$last_cmd_result" -ne 0 ]; then
        execute_command sudo journalctl -en 20 -u redis
        console_output 0 red "$last_cmd_stdout"
        return 1
    fi

    # Check if Redis is active
    console_output 1 gray "Checking if Redis service is active..."
    execute_command sudo systemctl is-active redis
    assertTrue "Redis service is not active" "$last_cmd_result"

    # Test Redis connectivity with retry loop
    console_output 1 gray "Testing Redis connectivity..."
    local max_attempts=10
    local attempt=1
    local ping_success=false

    while [ $attempt -le $max_attempts ]; do
        execute_command redis-cli ping
        if [ "$last_cmd_result" -eq 0 ] && [ "$last_cmd_stdout" = "PONG" ]; then
            ping_success=true
            console_output 1 gray "Redis responded after $attempt attempt(s)"
            break
        fi
        console_output 1 gray "Attempt $attempt/$max_attempts: Redis not ready yet, waiting..."
        sleep 1
        attempt=$((attempt + 1))
    done

    assertTrue "Redis ping failed after $max_attempts attempts" "$ping_success"

    # Stop Redis service for cleanup
    console_output 1 gray "Stopping Redis service for cleanup..."
    execute_command sudo systemctl stop redis
}

# Load shunit2 framework
# This should be the last line in the script
# shellcheck disable=SC1091
. "$(dirname "$0")/shunit2"
