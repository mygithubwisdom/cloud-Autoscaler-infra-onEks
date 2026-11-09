#!/usr/bin/env bash
set -Eeuo pipefail

# Task 3: Go API health and readiness verification.
# Default target is localhost. No AWS connection is required.

API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8080}"
API_BASE_URL="${API_BASE_URL%/}"

MAX_ATTEMPTS=5
RETRY_DELAY=2

for tool in curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf '[FAIL] Required tool missing: %s\n' "$tool" >&2
        exit 1
    fi
done

check_endpoint() {
    local endpoint="$1"
    local filter="$2"
    local attempt
    local response

    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        if response=$(curl -fsS \
            --connect-timeout 3 \
            --max-time 5 \
            "${API_BASE_URL}${endpoint}" 2>/dev/null); then

            if jq -e "$filter" >/dev/null 2>&1 <<< "$response"; then
                printf '[PASS] %s\n' "$endpoint"
                return 0
            fi
        fi

        printf '[RETRY] %s attempt %d/%d\n' \
            "$endpoint" "$attempt" "$MAX_ATTEMPTS" >&2

        if ((attempt < MAX_ATTEMPTS)); then
            sleep "$RETRY_DELAY"
        fi
    done

    printf '[FAIL] %s did not return the expected response\n' \
        "$endpoint" >&2
    return 1
}

echo "========================================"
echo "Task 3 - API Health Verification"
echo "========================================"
echo "Target: ${API_BASE_URL}"
echo

check_endpoint "/health" '.status == "healthy"'
check_endpoint "/ready" '.status == "ready"'
check_endpoint "/api/version" '.version | type == "string" and length > 0'

echo
echo "[PASS] All API health checks completed."
