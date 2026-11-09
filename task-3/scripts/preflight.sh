#!/usr/bin/env bash
set -uo pipefail

# Task 3: Local deployment prerequisite checks.
# This script does not connect to AWS or provision infrastructure.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

failures=0

check_command() {
    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        printf '[PASS] %s is installed\n' "$command_name"
    else
        printf '[FAIL] %s is not installed\n' "$command_name"
        failures=$((failures + 1))
    fi
}

check_directory() {
    local directory="$1"

    if [[ -d "${REPO_ROOT}/${directory}" ]]; then
        printf '[PASS] %s exists\n' "$directory"
    else
        printf '[FAIL] %s is missing\n' "$directory"
        failures=$((failures + 1))
    fi
}

echo "========================================"
echo "Task 3 - Local Deployment Preflight"
echo "========================================"

echo
echo "Checking required tools..."

check_command terraform
check_command aws
check_command kubectl
check_command helm
check_command docker
check_command curl
check_command git

echo
echo "Checking project directories..."

check_directory "task-1/infra"
check_directory "task-2-cicd"
check_directory "task-3/scripts"

echo
echo "========================================"

if (( failures > 0 )); then
    printf 'Preflight FAILED: %d check(s) failed.\n' "$failures"
    exit 1
fi

echo "Preflight PASSED: All local prerequisites are available."

