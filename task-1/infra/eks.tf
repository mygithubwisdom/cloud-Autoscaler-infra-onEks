#node group for EKS cluster
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "assessment-workers"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.medium"]
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
