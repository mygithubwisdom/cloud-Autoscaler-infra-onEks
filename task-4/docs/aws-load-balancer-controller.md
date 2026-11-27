# AWS Load Balancer Controller

## 1. Overview

The AWS Load Balancer Controller manages Application Load
Balancers and target groups for Kubernetes Ingress resources
running on Amazon EKS.

The application uses an internet-facing ALB with IP targets,
HTTPS termination through ACM, and a Kubernetes ClusterIP
Service.

Terraform manages the underlying infrastructure, IAM roles
and security group rules. The controller manages the ALB,
listeners, listener rules and target groups.

## 2. Version Selection

| Component | Version |
|---|---|
| Helm chart | 3.7.0 |
| Controller image | v3.7.0 |
| Kubernetes | 1.36 |
| Kubernetes client libraries | v0.36.2 |
| Controller runtime | v0.24.1 |

The controller image is:

public.ecr.aws/eks/aws-load-balancer-controller:v3.7.0

Version v2.14.1 was rejected after vulnerability scanning
reported 34 HIGH and 1 CRITICAL fixable vulnerability findings.

Version v3.7.0 passed the Trivy vulnerability scan with zero
fixable HIGH or CRITICAL findings for linux/amd64.

Unfixed vulnerabilities and lower severity findings were
excluded from this acceptance gate.

## 3. Helm Configuration

The permanent configuration is maintained in:

[helm-values/aws-load-balancer-controller.yaml](../helm-values/aws-load-balancer-controller.yaml)

The Helm chart must be explicitly pinned to version 3.7.0
during rendering and deployment.

| Setting | Value |
|---|---|
| Namespace | kube-system |
| Cluster name | assessment-cluster |
| AWS region | us-east-1 |
| Replicas | 2 |
| Ingress class | alb |
| Image pull policy | IfNotPresent |
| Controller autoscaling | Disabled |
| Backend security group | Disabled |
| Backend SG rule management | Disabled |
| Service mutator webhook | Disabled |

The Service mutator webhook is disabled because the application
uses a ClusterIP Service behind an ALB Ingress.

## 4. IAM and IRSA

The controller uses IAM Roles for Service Accounts (IRSA).

Service account identity:

system:serviceaccount:kube-system:aws-load-balancer-controller

The IAM role is provisioned by Task 1 Terraform configuration.

The upstream IAM policy is pinned to v3.7.0 and maintained at:

task-1/infra/policies/alb-controller-v3.7.0.json

Terraform applies additional restrictions to security group
permissions:

- Restricts ingress rule modification to security groups
  within the project VPC.
- Restricts security group deletion using the VPC and
  exact cluster ownership tag.
- Preserves unrelated upstream policy statements.

The representative hardened IAM policy passed AWS IAM Access
Analyzer policy validation with zero findings.

This does not independently establish effective runtime
permissions or complete least privilege.

## 5. Deployment-Time Dependencies

The following values are intentionally empty in the permanent
Helm configuration and must be supplied during deployment.

| Helm value | Terraform output |
|---|---|
| vpcId | vpc_id |
| ServiceAccount role ARN annotation | workload_role_arns.alb_controller |

The actual VPC ID and IAM role ARN must be obtained from
the deployed Task 1 infrastructure.

Representative validation values must not be used for
production deployment.

## 6. Gateway API Configuration

The application uses Kubernetes Ingress rather than Gateway API.

The following feature gates are explicitly disabled:

- ALBGatewayAPI
- NLBGatewayAPI
- GatewayListenerSet

Version-pinned controller source inspection confirmed that
these feature gates are enabled by default.

Explicitly configuring all three gates bypasses Gateway CRD
auto-detection. Disabling both ALB and NLB Gateway features
also skips common Gateway controller initialization.

Standard Kubernetes Gateway API CRDs are therefore not planned
for installation in this Ingress-only architecture.

Runtime startup validation remains required.

## 7. Custom Resource Definitions

All seven CRDs packaged with Helm chart v3.7.0 are retained:

- albtargetcontrolconfigs.elbv2.k8s.aws
- globalaccelerators.aga.k8s.aws
- ingressclassparams.elbv2.k8s.aws
- targetgroupbindings.elbv2.k8s.aws
- listenerruleconfigurations.gateway.k8s.aws
- loadbalancerconfigurations.gateway.k8s.aws
- targetgroupconfigurations.gateway.k8s.aws

The IngressClassParams and TargetGroupBinding CRDs are
particularly relevant to the application architecture.

Helm installs packaged CRDs during initial installation.
Existing CRDs require separate lifecycle management during
chart upgrades.

CRD upgrades must use reviewed, version-pinned definitions.

## 8. Resource Allocation and Availability

| Resource | Per replica | Two replicas |
|---|---|---|
| CPU request | 100m | 200m |
| Memory request | 128Mi | 256Mi |
| Memory limit | 256Mi | 512Mi |

No CPU limit is configured.

Preferred pod anti-affinity encourages distribution across
worker nodes without guaranteeing separate placement.

The controller uses the system-cluster-critical priority class.

Health probes:

- Liveness: /healthz on port 61779.
- Readiness: /readyz on port 61779.

Resource allocations are initial settings and remain subject
to runtime observation.

## 9. Offline Validation

Validation completed on 27 November 2026.

| Check | Result |
|---|---|
| Version-pinned Helm chart review | Passed |
| Fixable HIGH/CRITICAL vulnerability scan | Passed |
| IAM policy migration | Passed |
| Representative IAM policy validation | Passed |
| Kubernetes client library alignment | Confirmed |
| Gateway feature gate source review | Passed |
| Helm lint | Passed |
| Helm manifest rendering | Passed |
| Controller arguments | Passed |
| IRSA ServiceAccount rendering | Passed |
| Service mutator webhook exclusion | Passed |
| Resource allocations | Passed |
| Health probes and affinity | Passed |
| Rendered CRD inventory | Passed |

Temporary rendered manifests must not be committed because
they contain generated webhook TLS material.

## 10. Outstanding Runtime Validation

- [ ] Controller pods become Ready.
- [ ] IRSA successfully assumes the intended IAM role.
- [ ] Controller AWS API permissions operate as intended.
- [ ] Admission webhooks are reachable.
- [ ] Gateway controllers remain disabled.
- [ ] Ingress reconciliation creates the expected ALB.
- [ ] Target groups register healthy application pod IPs.
- [ ] HTTPS termination works with the ACM certificate.
- [ ] Terraform-managed security group rules remain intact.
- [ ] Controller resource consumption remains acceptable.
- [ ] ALB resources are removed successfully during cleanup.

Offline validation does not constitute successful deployment.

## 11. Upstream References

- https://github.com/kubernetes-sigs/aws-load-balancer-controller/tree/v3.7.0
- https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/tag/v3.7.0
- https://aws.github.io/eks-charts
- https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
