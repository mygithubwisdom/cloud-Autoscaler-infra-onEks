resource "aws_security_group" "eks_nodes" {
  name_prefix = "${local.name_prefix}-nodes-"
  description = "Private EKS worker ENIs and ordinary VPC CNI pods"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name                                        = "${local.name_prefix}-nodes"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}
resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  description = "HTTPS frontend and API backend"
  vpc_id      = aws_vpc.main.id
}
resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  description = "Private PostgreSQL from EKS nodes; pod access further restricted by NetworkPolicy"
  vpc_id      = aws_vpc.main.id
}
resource "aws_vpc_security_group_ingress_rule" "https_to_alb" {
  for_each          = var.public_https_cidrs
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Public HTTPS visitors"
}
resource "aws_vpc_security_group_ingress_rule" "http_redirect_to_alb" {
  for_each          = var.enable_http_redirect ? var.public_https_cidrs : toset([])
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP redirect only; Ingress must configure redirect to HTTPS"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = var.api_port
  to_port                      = var.api_port
  description                  = "ALB IP targets and health checks on API port"
}
resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.api_port
  to_port                      = var.api_port
  description                  = "API traffic from ALB"
}
resource "aws_vpc_security_group_ingress_rule" "eks_to_rds" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from worker ENIs; require app NetworkPolicy too"
}
resource "aws_vpc_security_group_ingress_rule" "nodes_to_api_server" {
  security_group_id            = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Workers to private Kubernetes API"
}
resource "aws_vpc_security_group_ingress_rule" "control_plane_to_nodes" {
  for_each                     = { kubelet = 10250, alb_webhook = 9443 }
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  description                  = "Control plane to ${each.key}"
}
# EKS-created cluster SG keeps AWS-managed self rules and default egress.
# Internal node/pod traffic is intentionally broad. Task 4 NetworkPolicies
# must restrict API, DNS, monitoring and DB flows; SGs cannot select pod labels.
resource "aws_vpc_security_group_ingress_rule" "node_internal" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "-1"
  description                  = "Internal node and ordinary pod communication"
}
resource "aws_vpc_security_group_egress_rule" "node_outbound" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Sandbox outbound via NAT; review destination inventory before restricting"
}
resource "aws_vpc_security_group_ingress_rule" "private_api_clients" {
  for_each                     = var.private_api_client_security_groups
  security_group_id            = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Private API for ${each.key}; source also needs egress and VPC routing"
}
