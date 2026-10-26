# This is an EKS worker launch template, not a standalone application server.
# EKS chooses/bootstraps the optimized AMI; no app user data, key pair or profile.
resource "aws_launch_template" "eks_nodes" {
  name_prefix            = "${local.name_prefix}-workers-"
  update_default_version = true
  vpc_security_group_ids = [aws_security_group.eks_nodes.id]
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-worker" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }
}
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "assessment-workers"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = local.private_subnet_ids
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD"
  release_version = var.node_ami_release_version
  capacity_type   = "ON_DEMAND"
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = tostring(aws_launch_template.eks_nodes.latest_version)
  }
  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }
  update_config { max_unavailable = 1 }
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
    precondition {
      condition = var.node_min_size >= 2 && var.node_min_size <= var.node_desired_size && var.node_desired_size <= var.node_max_size && alltrue([
        for size in [var.node_min_size, var.node_desired_size, var.node_max_size] : floor(size) == size
      ])
      error_message = "Use integer sizes with 2 <= min <= desired <= max."
    }
  }
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni,
    aws_vpc_security_group_ingress_rule.nodes_to_api_server,
    aws_vpc_security_group_ingress_rule.control_plane_to_nodes,
    aws_vpc_security_group_ingress_rule.node_internal,
    aws_vpc_security_group_egress_rule.node_outbound,
    aws_route.private_nat,
    aws_route.public_internet,
    aws_route_table_association.public,
    aws_route_table_association.private
  ]
}
# EKS creates the ASG; tag that ASG instead of creating a second one.
resource "aws_autoscaling_group_tag" "cas" {
  for_each = {
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }
  autoscaling_group_name = aws_eks_node_group.workers.resources[0].autoscaling_groups[0].name
  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = true
  }
}
