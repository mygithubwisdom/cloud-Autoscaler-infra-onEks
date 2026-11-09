# Task 3 — Deployment Scripts and Validation

## Overview

Task 3 provides Bash scripts for validating Terraform infrastructure configuration, preparing for EKS connectivity, and verifying the health of the Go REST API.

The current implementation supports local testing without provisioning AWS resources.

## Project Structure

```text
task-3/
├── scripts/
│   ├── preflight.sh
│   ├── plan.sh
│   ├── apply.sh
│   ├── connect-eks.sh
│   └── healthcheck.sh
├── tests/
│   └── test-healthcheck.sh
├── endpoints.example.txt
└── README.md
```

## Script Descriptions

| Script | Purpose |
|---|---|
| `preflight.sh` | Checks required tools and project directories |
| `plan.sh` | Runs Terraform formatting and configuration validation |
| `apply.sh` | Prevents unauthorized infrastructure deployment |
| `connect-eks.sh` | Checks AWS CLI and kubectl availability while blocking live cluster access |
| `healthcheck.sh` | Verifies the Go API health, readiness and version endpoints |

## Local Validation

Run all commands from the repository root.

### 1. Check prerequisites

```bash
./task-3/scripts/preflight.sh
```

### 2. Validate Terraform

```bash
./task-3/scripts/plan.sh validate
```

This runs Terraform formatting checks, initialization with the remote backend disabled, and configuration validation.

Provider downloads may require internet access. No AWS infrastructure is provisioned.

### 3. Verify deployment safeguards

```bash
./task-3/scripts/plan.sh plan
./task-3/scripts/apply.sh
./task-3/scripts/connect-eks.sh
```

These commands intentionally block live operations and return exit code `2`.

### 4. Start the Go API

From the repository root:

```bash
cd task-2-cicd
go run ./cmd/api
```

The API listens on port `8080` by default.

### 5. Run health checks

In another terminal, from the repository root:

```bash
./task-3/scripts/healthcheck.sh
```

The script checks:

- `GET /health` — expects `{"status":"healthy"}`
- `GET /ready` — expects `{"status":"ready"}`
- `GET /api/version` — expects a nonempty version string

To test another API address:

```bash
API_BASE_URL="http://127.0.0.1:8080" ./task-3/scripts/healthcheck.sh
```

### 6. Run the negative test

```bash
./task-3/tests/test-healthcheck.sh
```

This verifies that an unavailable local API causes the health-check script to fail.

## Validation Results

The following checks passed locally on 9 November 2026:

- Required tool and directory checks
- Terraform offline validation
- Terraform planning safeguard
- Terraform apply safeguard
- EKS connectivity safeguard
- Positive API health checks
- Negative API health-check test

## Deployment Status

AWS infrastructure deployment is intentionally disabled.

The following activities remain pending:

- Confirming the target AWS account and environment
- Reviewing the remote Terraform state backend
- Reviewing a real Terraform execution plan
- Authorizing Terraform deployment
- Establishing EKS cluster connectivity
- Deploying the containerized Go API to Kubernetes
- Running health checks against the deployed application

Successful local validation does not imply that the EKS cluster or application has been deployed.

## Security Considerations

- Do not commit Terraform state files or saved execution plans.
- Do not commit AWS credentials or other secrets.
- Verify the AWS account, Region and backend before enabling live operations.
- Require explicit authorization before infrastructure changes.
- Keep production deployment disabled during local development.
