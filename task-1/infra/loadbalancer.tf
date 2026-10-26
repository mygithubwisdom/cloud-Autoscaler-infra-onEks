resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [
    aws_subnet.Publicsubnet.id,
    aws_subnet.Publicsubnet_b.id
  ]

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

# ALB -> pod IP on container port, NOT Service port or NodePort.
resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  description                 = "API requests and health checks"
  ip_protocol                 = "tcp"
  from_port                   = var.api_port
  to_port                     = var.api_port
}
resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.alb.id
  description                 = "API and health checks from ALB only"
  ip_protocol                 = "tcp"
  from_port                   = var.api_port
  to_port                     = var.api_port
}
# Pods/nodes -> PostgreSQL. NetworkPolicy further limits which pods may use it.
resource "aws_vpc_security_group_ingress_rule" "eks_to_rds" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  description                 = "PostgreSQL from EKS worker ENIs"
  ip_protocol                 = "tcp"
  from_port                   = 5432
  to_port                     = 5432
}
# Workers -> private Kubernetes API endpoint.
resource "aws_vpc_security_group_ingress_rule" "nodes_to_api_server" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  description                 = "Workers and controllers to Kubernetes API"
  ip_protocol                 = "tcp"
  from_port                   = 443
  to_port                     = 443
}
# Control plane -> kubelet and the default AWS Load Balancer Controller webhook.
# Add an explicitly reviewed port if another admission webhook actually needs it.
resource "aws_vpc_security_group_ingress_rule" "control_plane_to_nodes" {
  for_each = {
    kubelet      = 10250
    alb_webhook  = 9443
  }
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = var.cluster_security_group_id
  description                 = "EKS control plane to ${each.key}"
  ip_protocol                 = "tcp"
  from_port                   = each.value
  to_port                     = each.value
}