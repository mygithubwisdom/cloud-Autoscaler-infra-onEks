# Task 1 — Implementation and Validation Checks

**Updated:** 6 November 2026
**Original reviewed base:** `cd98d5f07b87ad28c261102f6ec599a2c0a79c89`
**Scope:** Task 1 infrastructure, bootstrap, documentation, Terraform validation workflow, Terraform tests, ignore rules and security scanning.

> **Deployment status:** No infrastructure was deployed during this review. A successful `plan`, `validate`, `test`, or Trivy scan is not a live AWS deployment test.

## 1. Completed static checks (earlier review)

- [x] Terraform **1.15.8** archive checksum matched the published release checksum.
- [x] `terraform fmt -check -recursive task-1` passed in the earlier review.
- [x] All Task 1 Terraform HCL and mock test files parsed with `python-hcl2`.
- [x] Static checks found no duplicate resource addresses or undeclared variable/resource references.
- [x] No standalone application EC2 instance, ALB, target group or ASG Terraform resource remained in the reviewed configuration. The application ALB is intended to be managed through Kubernetes integration.
- [x] Vendored ALB Controller policy parsed as valid JSON and matched pinned upstream **v2.14.1** in the earlier check.
- [x] Main provider lock included verified `linux_arm64` and `linux_amd64` checksums.
- [x] Existing GitHub OIDC identities, bootstrap bucket resources and AWS state were not changed during the earlier review.
- [x] With owner confirmation, `backend.prod.hcl` was corrected to the already-initialized remote state key. **No state migration occurred.** Exact backend identifiers are intentionally excluded from this public report.

## 2. Local Terraform execution — updated results

| Check | Evidence / result | Status |
|---|---|---|
| Earlier isolated execution environment | Provider startup blocked: `listen unix /tmp/plugin...: socket: operation not permitted` | **Inconclusive in that environment**; never counted as a pass |
| Bootstrap validation | `terraform -chdir=task-1/bootstrap validate` → `Success! The configuration is valid.` | **PASS** on Linux workstation |
| Infra validation | `terraform -chdir=task-1/infra validate` → `Success! The configuration is valid.` | **PASS** on Linux workstation |
| Infra mock tests | `terraform -chdir=task-1/infra test` → **4 passed, 0 failed** | **PASS** |
| Infra plan | Reviewed plan displayed **79 to add, 0 to change, 0 to destroy** | **Plan generated**, not applied; results can change |
| Git protection | `git check-ignore -v` matched `*.tfplan` and `*.tfstate` | **PASS** for the checked paths |
| Git tracking | `git ls-files -- ...` produced no tracked entries for bootstrap plan/state | **PASS** for the checked paths |
| Terraform apply / AWS resources | Not performed during this review | **NOT DONE** |

### Test cases visible in the supplied terminal screenshot

```text
run "network_and_identity_baseline" ... pass
run "reject_world_open_cluster_api" ... pass
run "reject_missing_cluster_api_allowlist" ... pass
run "reject_invalid_node_bounds" ... pass
Success! 4 passed, 0 failed.
```

These are Terraform tests (including mock-based checks), not evidence that EKS nodes or the ALB are running.

## 3. Trivy security review — updated 5–6 November 2026

### Infra scan

```bash
trivy config --tf-vars task-1/infra/terraform.tfvars \
  --severity HIGH,CRITICAL task-1/infra/
```

Latest shared scan summary: **one CRITICAL finding**, AWS-0104 in `security-groups.tf`; all other displayed Terraform targets reported zero findings **after configured exceptions**.

| ID | Severity | Disposition | Remaining concern |
|---|---|---|---|
| AWS-0039 | HIGH | Suppressed | EKS 1.36 uses EKS 1.28+ default envelope encryption; customer-managed key requirement remains policy-dependent |
| AWS-0040 | CRITICAL | Suppressed | Public EKS API is intentionally enabled for sandbox access |
| AWS-0041 | CRITICAL | Suppressed | Public API restricted to a trusted `/32`; still publicly reachable from that address |
| AWS-0132 — ALB logs | HIGH | Resource-specific inline suppression | SSE-S3 used because ALB log delivery does not support SSE-KMS |
| AWS-0132 — bootstrap state | HIGH | Resource-specific inline suppression | State uses SSE-S3, not a customer-managed KMS key |
| **AWS-0104** | **CRITICAL** | **OPEN, not suppressed** | EKS node outbound TCP/443 permits `0.0.0.0/0` through NAT |

### Bootstrap scan and saved-plan behavior

The first bootstrap scan reported AWS-0132 again as `terraformplan-snapshot` because a saved `bootstrap.tfplan` was scanned separately. Trivy logged recognition of the source-code inline exception, but the plan snapshot still showed a finding. Re-running with the saved plan explicitly skipped:

```bash
trivy config --severity HIGH,CRITICAL \
  --skip-files task-1/bootstrap/bootstrap.tfplan task-1/bootstrap/
```

returned **zero reported HIGH/CRITICAL findings in the Terraform source**. This is a source-only result; the saved plan's finding has not been remediated or separately waived.

Trivy warned that `owner` and `state_bucket_name` variable values were not supplied to the bootstrap scan. That warning limits complete variable resolution; it is not proof that the deployed AWS resources lack those values.

## 4. Architecture checks from source review

- [x] Private worker subnet route table uses a NAT Gateway in a public subnet for default outbound routing.
- [x] Database subnet route table is isolated from the default internet route in the reviewed code.
- [x] S3 Gateway Endpoint is associated with the private route table.
- [x] Optional SSM/SSM Messages interface endpoints are conditional; reviewed `enable_ssm_endpoints=false`.
- [x] Node-to-RDS security-group egress is scoped to TCP/5432.
- [x] Node-to-node egress references the same EKS node security group.
- [x] ALB-to-API egress references the EKS node security group on the configured application API port.
- [ ] **AWS-0104 unresolved:** Node HTTPS egress remains open to all IPv4 destinations on TCP/443.
- [ ] Live EKS endpoint, node registration, pod networking, ALB controller/ingress, certificate, DNS and database connectivity **not verified**.

## 5. Tooling and debugging checks

- [x] Node.js upgraded from **20.20.1** to **24.22.2**, npm **11.19.1** verified on Debian ARM64.
- [x] Terraform debug workflow documented with `TF_LOG=DEBUG`, `TF_LOG_PATH`, `.env`, `source .env`, environment-variable checks and log inspection/clearing.
- [x] Trivy local version **0.76.1** used for the reported scans.
- [ ] HashiCorp APT repository missing-key warning observed during Node.js setup; resolution **not verified**.
- [ ] Task 2 GitHub Actions image scan showed HIGH/CRITICAL Go dependency vulnerabilities; **Task 2 CI not yet confirmed passing**.

## 6. Not completed / not proven

- [ ] AWS identity and IAM role assumption verified against live account.
- [ ] AWS quotas, regional Kubernetes/add-on availability, service-linked roles, cost/budget controls verified.
- [ ] AWS runtime connectivity, EKS node registration, ALB target health, RDS access, logging and autoscaling validated.
- [ ] Full deployment and post-deployment smoke tests completed.
- [ ] AWS-0104 risk remediated or explicitly approved under a documented acceptance process.
- [ ] Task 2 image vulnerability findings fixed and CI rerun successfully.
- [ ] Production-grade least-privilege egress and service endpoints reviewed.

## 7. Reproduction commands (no deployment)

Run from the repository root:

```bash
terraform fmt -check -recursive task-1
terraform -chdir=task-1/bootstrap validate
terraform -chdir=task-1/infra validate
terraform -chdir=task-1/infra test
trivy config --tf-vars task-1/infra/terraform.tfvars --severity HIGH,CRITICAL task-1/infra/
trivy config --severity HIGH,CRITICAL --skip-files task-1/bootstrap/bootstrap.tfplan task-1/bootstrap/
git check-ignore -v task-1/bootstrap/bootstrap.tfplan task-1/bootstrap/terraform.tfstate
git ls-files -- task-1/bootstrap/bootstrap.tfplan task-1/bootstrap/terraform.tfstate
```

**Safety:** No `terraform apply`, backend reconfiguration, state migration or GitHub Actions deployment is part of this checklist. Never publish `terraform.tfvars`, state/plan files, secrets or debug logs.

## 8. Final engineering assessment

**Terraform source validation: PASS.** **Terraform mock tests: PASS (4/4).** **Security scan: NOT CLEAN (AWS-0104 CRITICAL remains).** **Live AWS deployment and connectivity: NOT TESTED.** This is the accurate status of Task 1 as of **6 November 2026**.

## 9. Engineering Trade-offs and Architectural Decisions

Task 1 was designed as a cost-conscious AWS development environment using Terraform, Amazon EKS, private worker subnets, an Application Load Balancer, Amazon RDS PostgreSQL, and controlled outbound connectivity.

The architecture balances cost, security, availability, and operational simplicity.

### Cost optimization

- **SSM interface endpoints:** Disabled using `enable_ssm_endpoints = false` to avoid additional interface endpoint charges. SSM connectivity remains dependent on appropriate IAM, agent configuration and network access.
- **NAT Gateway:** A single NAT Gateway provides outbound connectivity for private EKS nodes. This reduces baseline costs compared with multiple NAT Gateways but introduces a single-AZ dependency.
- **S3 Gateway Endpoint:** Provides private S3 routing without hourly gateway endpoint charges.
- **AWS service endpoints:** Additional ECR and STS interface endpoints were deferred to avoid unnecessary development-environment costs.
- **Encryption:** SSE-S3 was retained for the Terraform state bucket and ALB access logs, with documented security considerations.

### Security and networking

- EKS worker nodes are placed in private subnets.
- RDS is placed in isolated database subnets.
- The EKS public API endpoint is restricted to a trusted `/32` address.
- Private EKS API access remains enabled.
- EKS Kubernetes 1.36 uses default envelope encryption for Kubernetes API data, including Secrets.
- Outbound worker HTTPS access through NAT is retained pending destination-level restrictions.
- GitHub OIDC avoids storing long-lived AWS credentials in CI.

### Reliability and operations

- Managed EKS node groups reduce worker node lifecycle management.
- The ALB provides application routing and health checks.
- Terraform state is protected using S3 versioning, encryption, public access blocking, HTTPS enforcement and native lockfile support.
- Terraform configuration, testing and security scanning are performed before deployment.

### Validation and known limitations

Local Terraform validation succeeded, and the recorded Terraform test run passed four tests with no failures.

The infrastructure plan was generated but not applied.

Trivy security findings were reviewed individually. Documented exceptions were retained where appropriate, while AWS-0104 remains open because unrestricted outbound HTTPS destinations require further network hardening.

### Future improvements

- Evaluate private ECR, STS and other required AWS service endpoints.
- Review NAT Gateway resilience and multi-AZ networking.
- Tighten outbound security group rules after confirming service dependencies.
- Review customer-managed KMS requirements for production.
- Validate IAM permissions, AWS quotas, application connectivity and operational behavior in an authorized deployment environment.
