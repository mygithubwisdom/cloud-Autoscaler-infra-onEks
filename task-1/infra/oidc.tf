# This is the EKS issuer only. Existing GitHub OIDC resources are not managed here.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[length(data.tls_certificate.eks.certificates) - 1].sha1_fingerprint]
}
# Dedicated identities; no controller or application AWS rights on worker nodes.
resource "aws_iam_role" "workload" {
  for_each = {
    vpc_cni        = "system:serviceaccount:kube-system:aws-node"
    alb_controller = "system:serviceaccount:kube-system:aws-load-balancer-controller"
    app            = "system:serviceaccount:${var.application_namespace}:task-api"
    migration      = "system:serviceaccount:${var.application_namespace}:task-api-migrations"
  }
  name = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = each.value
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.workload["vpc_cni"].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_policy" "alb_controller" {
  name   = "${local.name_prefix}-alb-controller"
  policy = file("${path.module}/policies/alb-controller-v2.14.1.json")
}
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.workload["alb_controller"].name
  policy_arn = aws_iam_policy.alb_controller.arn
}
