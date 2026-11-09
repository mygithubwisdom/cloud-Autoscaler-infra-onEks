#!/usr/bin/env bash
set -Eeuo pipefail

# Verify healthcheck.sh fails when the API is unavailable.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HEALTHCHECK="${SCRIPT_DIR}/../scripts/healthcheck.sh"

echo "Testing healthcheck failure detection..."

# Use an intentionally unavailable local port.
if API_BASE_URL="http://127.0.0.1:59999" bash "$HEALTHCHECK"; then
    echo "[FAIL] Healthcheck incorrectly reported success."
    exit 1
else
    echo "[PASS] Healthcheck correctly detected an unavailable API."
fi
