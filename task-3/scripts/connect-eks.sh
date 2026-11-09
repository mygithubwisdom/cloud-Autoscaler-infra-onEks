#!/usr/bin/env bash
set -Eeuo pipefail

# Task 3: EKS connection preparation.
# Live AWS connectivity is disabled during development.

echo "========================================"
echo "Task 3 - EKS Connection"
echo "========================================"

echo

for tool in aws kubectl; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '[PASS] %s is installed\n' "$tool"
    else
        printf '[FAIL] %s is missing\n' "$tool" >&2
        exit 1
    fi
done

echo
echo "[BLOCKED] Live EKS connection is not enabled."
echo
echo "Before connecting, confirm:"
echo "  1. The EKS cluster has been provisioned."
echo "  2. The correct AWS account and Region."
echo "  3. The EKS cluster name."
echo "  4. IAM authorization to access the cluster."
echo "  5. Network access to the Kubernetes API endpoint."
echo
echo "No kubeconfig changes were made."

exit 2
