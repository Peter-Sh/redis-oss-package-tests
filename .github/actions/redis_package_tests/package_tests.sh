#!/bin/bash

# Redis Package Tests using shunit2
# This script tests Redis package installation and basic functionality

# Global variables for test control
should_skip=false
skip_reasons=()

# Special output function with 4-space indent and gray color
console_output() {
    printf "\033[90m    %s\033[0m\n" "$*"
}

# Helper function to print skip reasons
print_skip_reasons() {
    if [ ${#skip_reasons[@]} -gt 0 ]; then
        console_output "Skip reasons:"
        for reason in "${skip_reasons[@]}"; do
            console_output "  - $reason"
        done
    fi
}

# Helper function to check if OS ID matches requirement
require_id_like() {
    local required_id="$1"

    if [ -f /etc/os-release ]; then
        # Source the os-release file to get ID_LIKE and ID
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

# Test function to check Redis RPM installation requirements
test_redis_rpm_install_files() {
    # Reset test control variables
    should_skip=false
    skip_reasons=()
    # Check if REDIS_RPM_INSTALL_FILES is set and not empty
    if [ -z "$REDIS_RPM_INSTALL_FILES" ]; then
        should_skip=true
        skip_reasons+=("REDIS_RPM_INSTALL_FILES is not set or empty")
    fi

    # Check if OS is RedHat-like
    require_id_like "rhel"

    # If requirements not met, skip the test
    if [ "$should_skip" = true ]; then
        startSkipping "$(print_skip_reasons)"
        return
    fi

    yum_output=$(sudo yum install -y $REDIS_RPM_INSTALL_FILES 2>&1)
    ret=$?

    assertTrue "Failed to install Redis packages: $REDIS_RPM_INSTALL_FILES" "$ret"
    if [ "$ret" -ne 0 ]; then
        console_output "$yum_output"
    fi
}

# Test function to check if Redis server starts successfully via systemd
test_systemd_start_redis() {
    # Reset test control variables
    should_skip=false
    skip_reasons=()

    # Check requirements
    require_has_systemd

    # If requirements not met, skip the test
    if [ "$should_skip" = true ]; then
        startSkipping "$(print_skip_reasons)"
        return
    fi

    # Stop Redis if it's already running
    console_output "Stopping Redis service if running..."
    sudo systemctl stop redis || true

    # Start Redis service
    console_output "Starting Redis service..."
    sudo systemctl start redis
    ret=$?
    assertTrue "Failed to start Redis service" "$ret"

    # Check if Redis is active
    console_output "Checking if Redis service is active..."
    sudo systemctl is-active redis
    ret=$?
    assertTrue "Redis service is not active" "$ret"

    # Test Redis connectivity
    console_output "Testing Redis connectivity..."
    sleep 2  # Give Redis a moment to fully start

    # Try to ping Redis
    local ping_result
    ping_result=$(redis-cli ping 2>/dev/null)
    assertEquals "Redis ping failed" "PONG" "$ping_result"

    # Stop Redis service for cleanup
    console_output "Stopping Redis service for cleanup..."
    sudo systemctl stop redis || true
}

# Load shunit2 framework
# This should be the last line in the script
. "$(dirname "$0")/shunit2"
