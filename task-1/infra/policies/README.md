# AWS Load Balancer Controller IAM policy

`alb-controller-v2.14.1.json` is the unmodified upstream policy from:
https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v2.14.1/docs/install/iam_policy.json

It is checked in for review and reproducibility; no policy is downloaded during Terraform apply.
Task 1 creates its IAM role. Task 4 must install the reviewed compatible controller/chart,
annotate service account `kube-system/aws-load-balancer-controller` with the output role ARN,
and configure the VPC ID and Region explicitly (IMDS is restricted for ordinary pods).

The upstream policy has some wildcard discovery/create actions required by AWS APIs.
Review its tag conditions and permissions before production use. Do not attach this policy
or the CAS policy to your EC2 node role or an existing GitHub role.
