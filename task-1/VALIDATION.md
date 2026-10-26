# Implementation checks

Base reviewed: cd98d5f07b87ad28c261102f6ec599a2c0a79c89.
Scope: Task 1, its documentation, a Terraform validation workflow and ignore rules.

Completed locally:

- Terraform 1.15.8 archive checksum matched the published release checksum.
- `terraform fmt -check -recursive task-1` passed.
- All Task 1 Terraform HCL and mock test files parsed successfully with python-hcl2.
- Static checks found no duplicate resource addresses or undeclared variable/resource references.
- No standalone application EC2 instance, ALB, target group or ASG resource remains.
- Vendored ALB policy parsed as valid JSON and matched pinned upstream v2.14.1.
- Main provider lock includes verified linux_arm64 and linux_amd64 checksums.
- No backend key, existing GitHub OIDC identity, bootstrap bucket resource or state was changed.

Not completed locally:

- `terraform validate` and mock `terraform test`: provider startup was blocked by
  this execution environment (`listen unix /tmp/plugin...: socket: operation not permitted`).
  This is not a passing validation result. Run the supplied GitHub workflow or
  the README's backend-free commands on the Chromebook before a real AWS plan.
- AWS account/permissions, regional version availability, quotas, live connectivity,
  IAM runtime behavior, AWS plan and deployment were not checked. No AWS credentials
  were supplied and no AWS resources were provisioned.

Before deployment:

1. Reconcile initialized S3 state location (two existing keys differ; README explains).
2. Fill account/admin/public API CIDR and verified EKS/add-on/PostgreSQL inputs.
3. Review optional domain, Single-AZ RDS and single-NAT cost/availability choices.
4. Pass provider-backed validation/mock tests; review and explicitly approve a live plan.
5. Later complete Task 4 controller installs, credential bootstrap, Ingress/DNS and
   enforced NetworkPolicy. IAM definitions alone do not deploy those workloads.
