#!/usr/bin/env bash
set -Eeuo pipefail

# Task 3: Controlled Terraform deployment.
# AWS infrastructure deployment is intentionally disabled.

echo "========================================"
echo "Task 3 - Terraform Deployment"
echo "========================================"

echo
echo "[BLOCKED] Terraform apply is not enabled."
echo
echo "Before deployment, confirm:"
echo "  1. The intended AWS account and Region."
echo "  2. The correct Terraform state backend."
echo "  3. The infrastructure plan has been reviewed."
echo "  4. Deployment has been explicitly authorized."
echo
echo "No AWS infrastructure changes were made."

exit 2
