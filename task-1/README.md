# Task 1 AWS infrastructure for EKS

Task 1 owns a single `prod`-labelled portfolio environment in `us-east-1`.
It uses EKS with On-Demand EC2 managed nodes. The application runs in pods;
there is no standalone application EC2 ASG, Python service or Terraform ALB.
EKS creates the backing ASG and Cluster Autoscaler adjusts it after Task 4 installs CAS.

## Directories and ownership

- `bootstrap/`: the already-applied protected S3 state bucket. Its local state must be retained securely and excluded from Git. Do not re-create the bucket or reinitialize this directory against the main infrastructure state.
- `infra/`: one independent Terraform root for VPC, EKS, nodes, IAM/IRSA, SSM, RDS, ACM and the ALB log bucket. This root uses the existing remote backend.
- `infra/policies/`: pinned upstream ALB controller IAM document.
- `infra/tests/`: Terraform mock-provider tests; no live AWS calls.

Task 2 owns ECR and GitHub publishing IAM. Task 4 owns controller Helm releases,
API Helm resources, the migration/bootstrap Job, and the ALB created by Ingress.
Task 5 adds application observability. Do not define these resources twice.
Existing GitHub OIDC providers/roles and account-wide SSM preferences are not changed.

`.github/workflows/task-1-validate.yml` runs formatting, provider-backed validation
and the mock tests on a normal GitHub runner. It has read-only repository access,
no OIDC permission, no AWS credentials and no live plan/apply step.

## File map

| File | Responsibility |
|---|---|
| `versions.tf`, `.terraform.lock.hcl` | Provider constraints and reproducible selections |
| `providers.tf`, `locals.tf`, `variables.tf` | Region/account guard, tags, subnet layout and inputs |
| `vpc.tf` | Two public, two private worker and two isolated database subnets; IGW; one NAT |
| `security-groups.tf` | HTTPS/redirect, API backend, kubelet/webhook, DB and optional private admin paths |
| `eks.tf` | Cluster, private endpoint, restricted optional public endpoint, logs and administrator access entry |
| `node-group.tf` | EKS-compatible launch template, managed nodes and backing-ASG CAS tags |
| `oidc.tf`, `iam.tf`, `cas-iam.tf` | EKS OIDC, cluster/node roles and separate workload identities |
| `addons.tf` | Pinned VPC CNI with network policy support, kube-proxy and CoreDNS |
| `rds_database.tf` | Private encrypted PostgreSQL, backups, managed master credentials and app secret placeholder |
| `ssm.tf` | Worker session logging, optional private endpoints and unattached operator policy |
| `s3.tf` | Private SSE-S3 ALB log bucket, account/prefix-scoped delivery and 30-day retention |
| `route53_acm.tf` | Optional ACM certificate validation in an existing Route53 zone |
| `outputs.tf` | Non-secret IDs/ARNs needed for Task 4 |

## First check the backend identity

The checked-in `infra/backend.prod.hcl` is preserved exactly:

```hcl
bucket       = "my-goapi-cloudeks-bucket-wisdom"
key          = "task1-assessment/prod/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
```

The owner confirmed the initialized backend metadata on the Chromebook:
`my-goapi-cloudeks-bucket-wisdom`, `task1-assessment/prod/terraform.tfstate`,
`us-east-1`. The main backend configuration and bootstrap output now match
that existing location. No state was migrated. Keep this key unchanged.

If you move directories later, inspect local backend metadata before
reinitializing. Do not print or share the entire metadata/state file because it
can hold credentials.

From that original initialized directory, this prints only the backend location:

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path('.terraform/terraform.tfstate')
if p.exists():
    c = json.loads(p.read_text()).get('backend', {}).get('config', {})
    print({k: c.get(k) for k in ('bucket', 'key', 'region')})
else:
    print('No local backend metadata here; check the original project root too.')
PY
```

If it disagrees with `infra/backend.prod.hcl`, reconcile the intended location
before proceeding. Do not answer a migration prompt blindly and do not run
`-migrate-state` or `-reconfigure` as a workaround. Preserve the actual initialized
key and inventory existing state first. Bootstrap's descriptive output is not
authoritative evidence of which backend your infrastructure used.

## Fill required inputs

Terraform 1.15.8 is the project CLI pin (`.terraform-version` in this directory),
matching the owner's installed release. The HCL compatibility constraint allows
1.10 through 1.x. Commit provider lock files. Initialize/install using native
Linux ARM64 binaries on the Chromebook; local review can use AMD64.

From `task-1/infra/`:

```bash
aws sts get-caller-identity
cp -i terraform.tfvars.example terraform.tfvars
```

I will Edit the copy, replacing every placeholder:

- `aws_account_id`: actual intended account ID. It is an identifier, not a secret.
- `eks_admin_principal_arn`: an existing IAM role or user ARN authorized to administer this cluster. For SSO/assumed roles, use the IAM role ARN, not the `arn:aws:sts::...:assumed-role/.../session` ARN. Do not grant an untrusted principal cluster administration.
- `public_api_cidrs`: your actual public egress IP/32 or other reviewed narrow range. Do not use the documentation TEST-NET addresses from mock tests.
- `kubernetes_version`, `addon_versions`, `db_engine_version`: supported explicit versions, checked in the selected AWS Region. Placeholder strings are intentionally rejected. No old book release is chosen automatically.
- Optional `domain_name` and `hosted_zone_id`: both required to create and validate the certificate. These must refer to an existing public hosted zone you control. HTTPS application exposure must wait for this certificate and Task 4 Ingress setup.

Read-only version discovery (requires the corresponding AWS describe permissions):

```bash
aws eks describe-cluster-versions --region us-east-1 --output table

# Replace VERSION with the minor you have verified is supported.
aws eks describe-addon-versions --region us-east-1 \
  --kubernetes-version VERSION --addon-name vpc-cni --output table
aws eks describe-addon-versions --region us-east-1 \
  --kubernetes-version VERSION --addon-name coredns --output table
aws eks describe-addon-versions --region us-east-1 \
  --kubernetes-version VERSION --addon-name kube-proxy --output table
aws eks describe-addon-configuration --region us-east-1 \
  --addon-name vpc-cni --addon-version VERIFIED_CNI_VERSION

aws rds describe-db-engine-versions --region us-east-1 \
  --engine postgres --query 'DBEngineVersions[].EngineVersion' --output table
aws rds describe-orderable-db-instance-options --region us-east-1 \
  --engine postgres --engine-version VERIFIED_POSTGRES_VERSION \
  --db-instance-class db.t3.micro --output table
```

Choose a VPC CNI version whose schema supports `enableNetworkPolicy` on the
selected AL2023 nodes. Task 4 must deploy and test NetworkPolicies; enabling the
agent alone does not restrict application flows. Match kubectl to the supported
cluster version skew and CAS image minor version to the cluster minor version.
Check EC2 Standard On-Demand vCPU quotas: max four t3.medium nodes consume eight
vCPUs, and upgrades may need additional surge capacity. Confirm subnet free IPs
for pods and upgrades. No AWS quota was verified by offline tests.

## Local validation before an AWS plan

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```

`terraform test` uses mock providers even though the test run says `apply`:
that is a simulated apply, not a deployment. Its versions and account IDs are
synthetic fixtures, not deployable selections. Backend-free initialization only
installs providers; it does not connect this root to S3.

After backend reconciliation, proper account permissions and input review:

```bash
terraform init -backend-config=backend.prod.hcl
terraform plan -out=task1.tfplan
terraform show task1.tfplan
# Apply only after explicit review/approval of the real AWS plan:
terraform apply task1.tfplan
```

This rewrite assumes only bootstrap has been applied, as reported by the owner.
If the main state already contains resources, stop: resource addresses were
normalized, so review moved/import blocks before applying any proposed replacement.
Never accept an unexpected destroy/recreate plan.

Do not use `-target` to force a partial deployment or repeatedly force node desired
capacity. CAS owns desired capacity after installation; Terraform owns min/max.
No actual AWS plan or apply is included in the implementation checks.

## Network paths and security tradeoffs

- Visitors -> ALB TCP 443. TCP 80 is allowed only for a future HTTP-to-HTTPS redirect.
- ALB -> ordinary VPC CNI pod IPs TCP 8080 (configurable `api_port`). Use `target-type: ip`, a ClusterIP Service and a matching container listener; do not open public NodePorts.
- Nodes -> private Kubernetes API TCP 443.
- Control plane -> kubelet 10250 and ALB controller webhook 9443.
- EKS node SG -> RDS TCP 5432. RDS requires TLS via `rds.force_ssl=1`; clients must validate the RDS CA, not merely request encryption.
- Nodes share a self ingress rule for internal DNS/pod/metrics traffic. Outbound is deliberately broad through NAT. This is a documented sandbox baseline, not least-privilege egress. Use pod NetworkPolicy and review observed destinations before narrowing it.
- Worker nodes get no public IPs, SSH key, or inbound TCP 22 rule. Their launch template attaches only the custom node SG. EKS-created cluster SG retains its AWS default self rules/egress; do not attach extra permissive SGs to workers.
- Database subnets have no default internet route. The single NAT lives in public subnet A; an AZ-A outage removes outbound internet for both worker AZs. Cross-AZ NAT traffic can cost extra. RDS is Single-AZ by default as in the original sandbox; enable `db_multi_az` for a paid availability demonstration. The `prod` name does not remove these limits.
- Private API clients need routing/VPN and IAM/RBAC as well as an SG. Hosted GitHub runners have no automatic private access. Public API CIDRs must cover the actual runner egress or a designed VPC runner must be used.

## SSM operation

The worker role has AmazonSSMManagedInstanceCore, and nodes can reach public SSM
services through NAT. `enable_ssm_endpoints=true` optionally adds `ssm` and
`ssmmessages` interface endpoints; it does not remove NAT or privatize all other AWS APIs.
Verify the selected EKS AL2023 release includes a running SSM Agent. An SSM IAM
attachment alone does not start an absent/stopped agent.

An account administrator may attach `ssm_operator_policy_arn` to the appropriate
operator identity after reviewing it. This code does not attach anything to an
existing user/role. Use a dedicated operator role and session policy for federated
operators if their `${aws:userid}` session-ownership pattern differs. Default
actions restrict node session start by project/environment tags; do not casually
broaden those tags or grant StartSession on every document.

```bash
aws ssm describe-instance-information --region us-east-1
aws ssm start-session --region us-east-1 \
  --target i-REPLACE_WITH_WORKER_ID \
  --document-name PROJECT_SESSION_DOCUMENT_OUTPUT
```

The custom document streams sessions to the project CloudWatch log group. It does
not replace account-wide default preferences. For the intended logging behavior,
operators must select this document and must not be granted an alternate unlogged
StartSession path. SSM/CloudWatch logs are encrypted using service defaults; this
configuration does not provision a customer KMS key. Normal shell sessions are
privileged node access: use them for troubleshooting, not application installation.

## PostgreSQL and secret handoff

RDS creates/rotates its master secret, so no master password input or secret value
is stored in Terraform configuration. State still contains sensitive infrastructure
metadata and requires protection. The app secret is deliberately created without a
value: a restricted Task 4 bootstrap Job must create a limited SQL app user and
populate it. API pods get only that app-secret read permission. The separate
`task-api-migrations` identity can read master credentials and initialize/update
app-secret values; tightly restrict who can create workloads with that service
account. Do not deploy it as the regular API service account. Ongoing migrations
should use a limited migration SQL user where practical.

IRSA namespace defaults to `prod`; Task 4 must use this exact namespace and
service account names (`task-api`, `task-api-migrations`). Application code uses
parameterized SQL, bounded connection pools and validated TLS. Deletion protection
is enabled and final snapshots are required. Emptying the log bucket and explicitly
handling DB snapshots/secrets are teardown decisions; no forced deletion is enabled.

## Task 4 ALB and CAS handoff

Do not add aws_lb, aws_lb_target_group or a second aws_autoscaling_group here.
Install controllers with the output IRSA role ARNs, pinned chart/image versions,
explicit cluster/VPC/Region settings and appropriate Kubernetes RBAC. The pinned
upstream ALB policy is v2.14.1; review the compatible controller/chart before use.
CAS needs `kube-system/cluster-autoscaler`, its role annotation and ASG tag discovery.
Task 1 IAM alone does not install CAS or the controller. Keep controller metrics internal.

Add/merge these Ingress annotations only after Task 1 is applied and the bucket,
certificate and SG outputs are available:

```yaml
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/security-groups: REPLACE_WITH_ALB_SG_OUTPUT
alb.ingress.kubernetes.io/manage-backend-security-group-rules: "false"
alb.ingress.kubernetes.io/certificate-arn: REPLACE_WITH_VALIDATED_CERTIFICATE_ARN
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
alb.ingress.kubernetes.io/ssl-redirect: "443"
alb.ingress.kubernetes.io/healthcheck-path: /ready
alb.ingress.kubernetes.io/load-balancer-attributes: >-
  access_logs.s3.enabled=true,
  access_logs.s3.bucket=REPLACE_WITH_LOG_BUCKET_OUTPUT,
  access_logs.s3.prefix=alb
```

The API DNS alias is configured after the controller creates the ALB; Task 1
creates only the certificate-validation DNS record. Logging does not exist until
the Ingress enables it. Query `alb/AWSLogs/ACCOUNT/...` in S3 for request debugging;
CloudWatch native ALB metrics are separate. No public Prometheus/Grafana endpoint
is introduced by Task 1.

## References

- https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html
- https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html
- https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- https://docs.aws.amazon.com/eks/latest/best-practices/cas.html
- https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html
- https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
- https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/
