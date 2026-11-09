#!/usr/bin/env bash
set -Eeuo pipefail

# Task 3: Terraform validation and deployment planning.
# Default mode is offline validation only.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/task-1/infra"

MODE="${1:-validate}"

if [[ ! -d "$TERRAFORM_DIR" ]]; then
    echo "[FAIL] Terraform directory not found: $TERRAFORM_DIR" >&2
    exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
    echo "[FAIL] Terraform is not installed." >&2
    exit 1
fi

case "$MODE" in
    validate)
        echo "Running offline Terraform validation..."

        terraform -chdir="$TERRAFORM_DIR" fmt -check

        terraform -chdir="$TERRAFORM_DIR" init \
            -backend=false \
            -lockfile=readonly \
            -input=false

        terraform -chdir="$TERRAFORM_DIR" validate

        echo "[PASS] Terraform offline validation completed."
        ;;

    plan)
        echo "[BLOCKED] Live Terraform planning is not enabled."
        echo "Confirm the AWS account, state backend and environment first."
        exit 2
        ;;

    *)
        echo "Usage: $0 [validate|plan]" >&2
        exit 1
        ;;
esac
