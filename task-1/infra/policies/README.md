# AWS Load Balancer Controller IAM policy

## Upstream policy

`alb-controller-v3.7.0.json` is the unmodified upstream policy from:

https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.7.0/docs/install/iam_policy.json

It is checked in for review and reproducibility; no policy is downloaded during Terraform apply.

## IAM policy hardening

Task 1 dynamically transforms the upstream policy in `oidc.tf` before creating the IAM managed policy.

The hardening implementation:

- Restricts the targeted security group operations to the current AWS account and region.
- Restricts security group ingress authorization, revocation and deletion to the dedicated VPC.
- Requires the matching `elbv2.k8s.aws/cluster` resource tag for security group deletion.
- Preserves the existing conditions on the targeted upstream statements.
- Preserves all unrelated upstream policy statements.
- Derives infrastructure identifiers dynamically from Terraform resources and variables.

The upstream policy retains wildcard discovery and creation permissions required by AWS APIs. Ingress rule modifications remain permitted across security groups within the dedicated VPC.

## Policy validation

The hardened policy has undergone the following pre-deployment checks:

- Terraform configuration validation: passed.
- Dynamic security group ARN transformation: passed.
- Upstream statement preservation: 16 statements retained.
- Unrelated statement regression check: passed.
- Representative hardened policy size: 5,608 of 6,144 permitted characters.
- AWS IAM Access Analyzer validation: zero findings.

Policy size and Access Analyzer checks used representative infrastructure identifiers. Effective runtime authorization remains subject to deployment verification.

## Task 1 and Task 4 integration

Task 1 creates the dedicated IAM role and hardened managed policy.

Task 4 must install the reviewed compatible controller/chart, annotate service account `kube-system/aws-load-balancer-controller` with the output role ARN, and configure the VPC ID and Region explicitly (IMDS is restricted for ordinary pods).

## Security considerations

Review the upstream permissions, tag conditions and policy size whenever upgrading the controller.

Do not attach this policy or the Cluster Autoscaler (CAS) policy to the EC2 node role or an existing GitHub role.
