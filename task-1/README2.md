# Task 1 — AWS EKS Infrastructure with Terraform

**Engineering implementation and troubleshooting record · Updated 6 November 2026**

> **Status:** Terraform configuration and tests validated locally; infrastructure **not deployed** during this review. A Trivy **high-priority** finding, AWS-0104 (unrestricted HTTPS egress from EKS nodes), remains open. Security exceptions described below are not remediations.

## 1. Purpose and scope

Task 1 defines the AWS infrastructure for a containerized application running on Amazon Elastic Kubernetes Service (EKS). It uses Terraform to model the network, IAM roles, EKS cluster and managed worker nodes, application load-balancing prerequisites, PostgreSQL database, logging, storage, and access controls. The design deliberately separates public-facing entry points from private compute and isolated database subnets.

This document is a **reproducible learning record**, not a claim that the architecture has been deployed or load-tested. The exact code and provider versions in the repository are authoritative if they differ from this dated record.

![Task 1 architecture diagram](./assets/architecture.svg)

*Architecture is a design illustration, not proof of a deployed ALB or EKS cluster.*

### Request and network paths

1. **Client → ALB:** A user connects to the public Application Load Balancer over HTTPS (subject to the actual listener and certificate configuration).
2. **ALB → application pods:** The ALB forwards traffic to EKS application targets on the configured API port, with security-group rules allowing ALB-to-node/API communication and health checks. Kubernetes ingress, AWS Load Balancer Controller, target registration and application readiness must be configured and tested before claiming this works end to end.
3. **Application → RDS:** EKS workloads reach PostgreSQL in isolated database subnets via narrowly scoped port 5432 security-group access. Database credentials must be handled through a secrets mechanism, not committed to Git.
4. **Worker nodes → AWS services:** Private worker subnets have a default route through a NAT Gateway in a public subnet. A separate S3 **gateway endpoint** provides a private route to S3. Optional SSM/SSM Messages **interface endpoints** are controlled by `enable_ssm_endpoints` (currently disabled in the reviewed configuration).
5. **Cluster control plane:** EKS private API access is enabled. Public API access is intentionally enabled for a trusted `/32` operator address in the private, Git-ignored variable file. This is a sandbox exception, not a recommended unrestricted production configuration.

**Important distinction:** The NAT Gateway is an outbound route, not an inbound route into private worker nodes. An ALB needs its own target-registration, ingress and security-group configuration. The diagram shows intended connectivity, not a proven live data path.

## 2. Repository layout

```text
cloud-Autoscaler-infra-onEks/
├── .github/workflows/
│   ├── task-1-validate.yml       # Terraform validation workflow
│   └── task-2-cicd.yaml          # Go / container CI pipeline
├── .gitignore
├── .trivyignore                 # Documented scan exceptions
├── backend.hcl                  # Review before using; no secrets in Git
├── task-1/
│   ├── bootstrap/
│   │   ├── main.tf              # Terraform state S3 bucket
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── infra/
│       ├── backend.tf
│       ├── backend.prod.hcl
│       ├── providers.tf
│       ├── versions.tf
│       ├── variables.tf
│       ├── terraform.tfvars.example
│       ├── vpc.tf
│       ├── security-groups.tf
│       ├── eks.tf
│       ├── node-group.tf
│       ├── addons.tf
│       ├── iam.tf
│       ├── oidc.tf
│       ├── cas-iam.tf
│       ├── rds_database.tf
│       ├── s3.tf
│       ├── ssm.tf
│       ├── route53_acm.tf
│       ├── outputs.tf
│       ├── locals.tf
│       ├── policies/
│       └── tests/baseline.tftest.hcl
├── task-2-cicd/                 # Go app, Docker, API definition, CI-related infra
├── README.md
└── task-1/README.md            # This guide, if saved here
```

This is a representative tree from the supplied screenshots. Verify current file names with `find task-1 -maxdepth 3 -type f` before using it as a canonical inventory. `terraform.tfvars`, `.env`, Terraform plans/state, and log files must remain untracked.

### Evidence: proposed Terraform infrastructure

![Terraform plan showing proposed infrastructure outputs](./assets/terraform-plan-outputs.png)

*The plan shows values known after apply; it is not a deployment result.*

## 3. Local workstation and Linux ARM64 setup

**Host environment:** Debian-based Linux on **ARM64 / AArch64 (`linux_arm64`)**, using a Linux terminal and VS Code. Project working directory in the captured session:

```bash
/home/testuser1/cloud-Autoscaler-infra-onEks
```

The terminal prompt shows a Linux username and a project directory under `/home/testuser1`; the exact user account can vary between installations. Prefer `$HOME` in portable commands.

### Directory ownership, permissions, and Git

```bash
# From the Linux user's home directory
mkdir -p "$HOME/cloud-Autoscaler-infra-onEks"
cd "$HOME/cloud-Autoscaler-infra-onEks"
pwd
uname -m                         # Expected on this machine: aarch64
id                               # Inspect UID and group membership
ls -ld .                         # Inspect project-directory permissions
```

For a project owned by the current user, normal user ownership and restrictive file permissions are preferable to running all tooling with `sudo`. **Do not run `chmod -R 777`**. If the project is owned by another account, investigate ownership before changing it. The original exact `chmod`/`chown` commands used during setup were not supplied, so they are **not asserted as completed historical actions** here.

Typical private-file protection, **only if needed and after checking file ownership**, is:

```bash
chmod 700 "$HOME/.ssh"  # Only when this directory exists and is owned by you
chmod 600 task-1/infra/terraform.tfvars  # Only when the file exists
```

Use `git status`, `git check-ignore -v` and `git ls-files` to verify which files are tracked. In this project, `*.tfplan` and `*.tfstate` were verified ignored, and the specific bootstrap plan and state files were confirmed untracked.

### Inspection of workstation architecture.
- **cat /etc/os-release**
- **uname -m**
- **dpkg --print-architecture**
- **free -h**
- **df -h /**
- **lscpu**
- **aws --version**
- **terraform version**
- **docker version**
- **kubectl version --client**
- **helm version**


### Tools and compatibility

- **Terraform:** Version **1.15.8** archive checksum was verified against the published release checksum during the earlier implementation checks. The provider lock contains Linux ARM64 and AMD64 checksums.
- **AWS CLI:** Used for AWS tooling and identity verification when credentials are explicitly configured; do not embed credentials in scripts or documentation.
- **Trivy:** Local scan was run with **0.76.1**.
- **Node.js:** Upgraded from **v20.20.1** to **v24.22.2**, with **npm 11.19.1**, on Debian ARM64.
- **Go/Docker:** Relevant to Task 2; application module and Dockerfile are in `task-2-cicd/`.
- **VS Code/Git:** Used to review Terraform, run commands, and maintain GitHub workflows.

> A HashiCorp APT repository GPG error (`NO_PUBKEY`, key not present) was visible during Node.js setup. The Node.js installation completed, but this unrelated repository trust issue was **not shown resolved**. Do not bypass APT signature verification; repair the official keyring/repository configuration before relying on future updates.

## 4. Terraform infrastructure components

| Area | Configured design | Security/operational consideration |
|---|---|---|
| VPC and subnets | Public ALB/NAT subnets, private EKS worker subnets, isolated database subnets across two AZs | DB subnet route table has no NAT/IGW default route in the reviewed code |
| NAT and routing | NAT Gateway in a public subnet; private route table `0.0.0.0/0` to NAT | NAT incurs charges when deployed; outbound traffic still subject to SG controls |
| S3 endpoint | Gateway endpoint associated with private route table | Does not replace all AWS API connectivity |
| EKS | Kubernetes **1.36** targeted, managed node group, cluster control-plane logs | Confirm regional version/add-on compatibility at deployment time |
| EKS API | Private endpoint enabled; public endpoint scoped to a trusted `/32` via variables | Public exposure is a documented sandbox exception |
| Security groups | ALB→API, nodes→RDS TCP/5432, nodes→nodes, nodes→HTTPS TCP/443 | HTTPS to `0.0.0.0/0` is an open **high-priority** Trivy finding |
| RDS | Private PostgreSQL service | Protect credentials, backups, encryption, rotation and access at runtime |
| S3 logging | ALB log bucket with SSE-S3 (`AES256`), public-access blocking and lifecycle | ALB access logging requires SSE-S3; inline Trivy exception documented |
| SSM | Optional SSM and SSM Messages interface endpoints; session log group | `enable_ssm_endpoints=false` in reviewed variables; enabling costs extra |
| IAM/OIDC | Cluster, worker and workload roles; access controls and policies in Terraform | Verify trust policies, least privilege and live access before deployment |
| Route 53 / ACM | Terraform configuration present | Domain ownership, DNS validation and HTTPS listener need runtime verification |
| Cluster Autoscaler | IAM configuration present | Runtime deployment and behavior not yet proven |

### Kubernetes API encryption and Trivy AWS-0039

EKS **1.28 and later** enables default envelope encryption of Kubernetes API data, including Secrets, with an AWS-owned KMS key. Since the configuration targets **Kubernetes 1.36**, the original AWS-0039 recommendation to add `encryption_config` was evaluated against this newer EKS behavior. The finding was **suppressed with a documented exception** rather than adding a customer-managed key without a demonstrated requirement. This does **not** establish a customer-managed KMS encryption requirement has been met; revisit if organizational policy requires it.

AWS reference: <https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html>

### Network route reference

![Conceptual NAT outbound route](./assets/nat-route-explanation.svg)

*Private nodes reach external HTTPS destinations via NAT; the NAT route does not itself authorize inbound internet access.*

## 5. IAM roles, trust, and permissions

The following table distinguishes **required permissions** from **verified live permissions**. Terraform policy definitions and successful syntax checks do not prove AWS has accepted every runtime operation.

| Identity / role | Required permissions or trust | Task 1 status / next check |
|---|---|---|
| Setup identity | Assume project Terraform role; read quotas, resources, and optionally budgets | Verify actual role assumption and quotas before deployment |
| Terraform provisioning role | Project-scoped VPC, networking, SG, EKS, add-ons, IAM, ECR (if managed), RDS, S3, logs, secrets metadata | Configuration designed; confirm AWS permissions with a reviewed plan and IAM policy evaluation |
| Terraform state access | S3 `ListBucket`, state object read/write; `.tflock` read/write/delete for `use_lockfile=true`; KMS if SSE-KMS used | S3 backend defined; do not change backend key or migrate state without explicit review |
| Role delegation | Scoped `iam:PassRole` and service-linked-role creation where needed | Validate exact role ARNs and service principals |
| EKS cluster role | `AmazonEKSClusterPolicy`; trust `eks.amazonaws.com` | Role/policy configuration present; verify live binding |
| EC2 worker node role | `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly` or equivalent; EC2 trust | Verify node bootstrap, image pulls and least privilege |
| VPC CNI role | `AmazonEKS_CNI_Policy` for IPv4; ideally separate workload identity | Verify add-on identity and IAM attachment |
| Kubernetes administrator/operator | EKS access entry plus appropriate access policy or Kubernetes RBAC | Cluster admin and application deployment rights should be separated |
| Application workloads | Scoped access to required AWS APIs and secrets using workload identity | Task 2 integration and runtime verification pending |
| GitHub Actions OIDC | GitHub identity provider trust constrained to expected repository/branch/environment; `id-token: write` where needed | Inspect Task 1 validation vs Task 2 build/deploy roles separately; never give a validation workflow deployment permissions unnecessarily |

**Next task permissions:** Task 2 needs GitHub Actions permissions to test and scan Go code, build a container, authenticate to a container registry (e.g., ECR push/pull), and—**only when explicitly authorized**—deploy to EKS using a tightly scoped OIDC role and Kubernetes RBAC. No such deployment should be triggered by merely validating Task 1.

## 6. Engineering troubleshooting diary

This is a chronology reconstructed from supplied screenshots, scan outputs and discussion. Exact dates for every individual edit are not fully evidenced.

### A. Terraform structure, backends and safety

- Structured Terraform into **bootstrap** (S3 state bucket) and **infra** (main EKS stack), with dedicated backend configuration and tests.
- Checked the Terraform **1.15.8** archive checksum and provider lock compatibility for ARM64 and AMD64.
- Corrected the configured backend key to match the **already initialized** remote-state key, without performing a state migration. The exact key and bucket name are intentionally omitted from this public README.
- Reviewed `*.tfplan` and `*.tfstate` ignore rules. `git check-ignore -v` confirmed matching rules; `git ls-files` produced no tracked entries for the bootstrap plan/state files.
- Kept all work at the validation/plan/review stage: **no `terraform apply` was performed during these checks**.

### B. Terraform validation, mock tests and plan

- Earlier external execution environment could not start Terraform providers due to `listen unix /tmp/plugin...: socket: operation not permitted`. That was **not** recorded as a pass.
- Later, on the Linux workstation, `terraform -chdir=task-1/bootstrap validate` and `terraform -chdir=task-1/infra validate` returned **Success! The configuration is valid.**
- `terraform -chdir=task-1/infra test` completed **4 passed, 0 failed**, covering network/identity baseline and invalid-configuration rejection tests.
- An infrastructure `terraform plan` completed and showed **79 to add, 0 to change, 0 to destroy** at that point in the project. A plan is a proposal, **not proof of provisioning**; future plans may differ.
- Verified the infrastructure design has **no standalone application EC2 instance, application ASG or standalone Terraform-managed ALB** in the reviewed static checks. The ALB is intended to be created/managed through Kubernetes ingress and its controller, not necessarily as a standalone Terraform `aws_lb` resource.

### Evidence: validation and Terraform tests

![Successful Terraform validation and four tests](./assets/terraform-validation-and-tests.png)

![Four Terraform tests passed](./assets/terraform-tests-four-passed.png)

*Four Terraform tests passed; these are local checks, not live infrastructure tests.*

### C. Node.js 20 → Node.js 24 maintenance

During the development environment setup, the existing Node.js **20.20.1** was upgraded to **24.22.2** (npm **11.19.1**) on Debian ARM64 using the NodeSource Debian repository. The captured session included:

```bash
# Example commands from the maintenance process; review downloaded scripts first
curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh
less /tmp/nodesource_setup.sh
sudo -E bash /tmp/nodesource_setup.sh
sudo apt-get install -y nodejs
node -v
npm -v
```

The initial upgrade work encountered an APT **HashiCorp repository missing GPG key** warning. This did not establish that Node.js 20 itself was deprecated on that date; the upgrade was a tooling-maintenance and compatibility decision. In a professional engineering workflow, first check runtime support policy, project compatibility, package provenance and architecture; then verify versions and run the relevant tests. Do not claim the upgrade fixed Task 2's container vulnerability scan without a fresh successful scan.

### D. Terraform DEBUG logging and `.env`

The project used Terraform's built-in diagnostic logging to investigate configuration/provider behavior:

```bash
# Example local-only .env content; do not commit this file
export TF_LOG=DEBUG
export TF_LOG_PATH="$HOME/cloud-Autoscaler-infra-onEks/terraform.log"
```

From the repository root:

```bash
source .env
printf '%s\n' "$TF_LOG"
printf '%s\n' "$TF_LOG_PATH"
# Run a read-only Terraform command while logging is enabled:
terraform -chdir=task-1/infra validate
# Inspect logs:
less "$TF_LOG_PATH"
# Clear an old log before a new diagnostic session, only if no process is writing it:
: > "$TF_LOG_PATH"
# Disable verbose logging afterward:
unset TF_LOG TF_LOG_PATH
```

`TF_LOG` controls verbosity (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, `OFF` depending on Terraform support); `TF_LOG_PATH` selects the log file. **Changing `TF_LOG` does not automatically change the log filename.** Existing logs may be appended to; truncating them destroys earlier diagnostics. Logs can contain resource metadata and sensitive values, so keep them out of Git and redact before sharing. An `.env` file is **not** loaded automatically by a shell: `source .env` is required for the current shell session. `echo "$TF_LOG"` is blank until the variable is exported in that shell.

### E. Trivy IaC security scans (5–6 November)

For Terraform variables such as a trusted API CIDR, the scan included the local variable file:

```bash
trivy config --tf-vars task-1/infra/terraform.tfvars \
  --severity HIGH,CRITICAL task-1/infra/
```

**Latest Task 1 infra result:** 0 reported findings in `eks.tf`, `s3.tf`, `rds_database.tf`, `ssm.tf`, and `vpc.tf`; **1 outstanding** finding in `security-groups.tf`. The zeroes include documented suppressions.

| ID | Area | Review decision | Actual status |
|---|---|---|---|
| AWS-0039 | EKS Kubernetes API secret encryption | EKS 1.28+ default envelope encryption reviewed | Suppressed; no customer KMS added |
| AWS-0040 | Public EKS API | Intentional sandbox operator access, private endpoint also enabled | Suppressed; public endpoint still enabled |
| AWS-0041 | Public API CIDR | Operator address constrained to trusted `/32` | Suppressed; reassess before production |
| AWS-0132 | ALB log bucket encryption | SSE-S3 is required for ALB access logs | Inline, resource-specific suppression |
| AWS-0132 | Bootstrap state bucket encryption | SSE-S3 with versioning, public-access block, HTTPS-only policy and destroy protection | Inline, resource-specific suppression; no CMK |
| **AWS-0104** | EKS worker outbound HTTPS | TCP 443 to `0.0.0.0/0` through NAT | **OPEN — not suppressed** |

Trivy also scanned a saved bootstrap **`bootstrap.tfplan`** as a separate `terraformplan-snapshot`, reporting AWS-0132 even though the inline source exception was recognized. Excluding **only that saved plan** confirmed the Terraform source scan had zero reported HIGH/CRITICAL findings:

```bash
trivy config --severity HIGH,CRITICAL \
  --skip-files task-1/bootstrap/bootstrap.tfplan task-1/bootstrap/
```

This does **not** mean saved plans should never be scanned. For a release pipeline, scan both source and plans intentionally, and decide how to handle exceptions in each scan path. Do not suppress all occurrences of AWS-0132 globally.

### Evidence: remaining Trivy finding

![Trivy scan showing the AWS-0104 finding](./assets/trivy-infrastructure-scan.png)

*AWS-0104 remains open. The inline exceptions elsewhere reduce reported findings but do not change deployed security controls.*

### F. AWS-0104 egress investigation

The reviewed egress rules were:

- ALB security group → EKS nodes on the configured API port.
- EKS nodes → RDS security group on TCP/5432.
- EKS nodes → same node security group for internal communication.
- **EKS nodes → `0.0.0.0/0` on TCP/443** for outbound HTTPS through NAT.

The NAT route and S3 gateway endpoint were confirmed in Terraform. SSM interface endpoints are optional and currently disabled; ECR and STS interface endpoints were not defined in the reviewed configuration. Removing all outbound HTTPS without an alternative could break node initialization, container image pulls or AWS API access. **Decision:** keep the finding visible, do not call it fixed, and redesign/approve destination restrictions before production.

## 7. Validation and safe commands

Run these from the repository root on a workstation with the matching Terraform providers initialized. They do **not** deploy infrastructure:

```bash
terraform fmt -check -recursive task-1
terraform -chdir=task-1/bootstrap validate
terraform -chdir=task-1/infra validate
terraform -chdir=task-1/infra test
trivy config --tf-vars task-1/infra/terraform.tfvars --severity HIGH,CRITICAL task-1/infra/
```

The `terraform.tfvars` file may contain sensitive values: never print or commit it. Terraform `plan` can read the remote backend and create a lock; review backend and permissions before running it. **Do not run `terraform apply` or GitHub Actions deployment jobs as part of these documentation checks.**

See [VALIDATION.md](./VALIDATION.md) for completed, incomplete, and outstanding checks.

## 8. Remaining work and Task 2 handoff

1. **Resolve or explicitly accept AWS-0104** through a reviewed network design: determine required external destinations, consider ECR/STS/other VPC endpoints, and verify cost/availability. An endpoint alone does not remove a broad egress rule.
2. Review live AWS identity permissions, role assumption, service quotas, Kubernetes 1.36 availability and supported add-on versions before any authorized deployment.
3. Verify EKS access entries and scoped Kubernetes RBAC for operators, the ALB Controller, and workloads.
4. Verify Kubernetes ingress, HTTPS certificate/DNS, target group health checks, pod readiness and network paths only after deployment is explicitly authorized.
5. **Task 2:** build/test the Go application and container; resolve the GitHub Actions Trivy HIGH/CRITICAL image vulnerabilities seen in the provided screenshot (including `golang.org/x/net`/`net/http`-related findings). Re-run scans; don't document CI as passing yet.
6. Configure narrowly scoped ECR push/pull and GitHub OIDC roles for Task 2, and separate build permissions from any future EKS deployment permissions.
7. Review cost controls, CloudWatch retention, NAT charges, RDS backups, state access and disaster-recovery procedures.

### Evidence: Task 2 dependency (separate workflow)

![Task 2 image scan blocked before AWS authentication and ECR publishing](./assets/task2-ci-image-scan-failure.png)

*This failure is from Task 2, not the Task 1 Terraform validation workflow. The container build completed, but the vulnerability scan prevented subsequent OIDC/ECR publishing steps.*

## 9. Security and reproducibility rules

- Never commit `.env`, `terraform.tfvars`, credentials, private keys, `terraform.tfstate`, `*.tfplan`, or debug logs.
- Keep `terraform.tfvars.example` sanitized and use placeholder values.
- Treat S3 backend names/keys, account numbers, public operator IPs and exact IAM ARNs as private operational details unless intentionally approved for publication.
- Store remote state with restricted IAM permissions, versioning, encryption, HTTPS enforcement and locking.
- Document every Trivy suppression with **scope, reason and review condition**. A suppressed result is not proof of remediation.
- Review provider and policy versions; this document is a snapshot of the engineering work as of **6 November 2026**.

## 10. References

- [Terraform CLI documentation](https://developer.hashicorp.com/terraform/cli)
- [AWS EKS security and Kubernetes Secrets encryption](https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html)
- [AWS EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [AWS VPC endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [Trivy Terraform misconfiguration scanning](https://trivy.dev/latest/docs/scanner/misconfiguration/)
- [Trivy AWS-0104](https://avd.aquasec.com/misconfig/aws-0104)


## 11. Evidence handling and README naming

Screenshots are **cropped to the relevant evidence** to reduce accidental disclosure of account identifiers, IP addresses, editor variables, and unrelated terminal history. Inspect every image again before publishing publicly. Screenshots show the dated state of work, not the latest status of external services.

This file can be named `README2.md` without affecting the existing `README.md`. GitHub automatically displays `README.md` as a directory landing page; link to `README2.md` from it if you want readers to discover the extended engineering report. All image links here assume this file is stored in `task-1/` next to the `assets/` folder.
