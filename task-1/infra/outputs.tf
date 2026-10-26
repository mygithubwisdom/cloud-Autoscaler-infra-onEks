output "cluster_name" { value = aws_eks_cluster.main.name }
output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_security_group_id" { value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id }
output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_ids" { value = local.public_subnet_ids }
output "private_subnet_ids" { value = local.private_subnet_ids }
output "database_subnet_ids" { value = local.database_subnet_ids }
output "eks_node_security_group_id" { value = aws_security_group.eks_nodes.id }
output "alb_security_group_id" { value = aws_security_group.alb.id }
output "rds_security_group_id" { value = aws_security_group.rds.id }
output "access_logs_bucket_name" { value = aws_s3_bucket.access_logs.id }
output "alb_logs_prefix" { value = "alb" }
output "node_group_name" { value = aws_eks_node_group.workers.node_group_name }
output "node_asg_name" { value = aws_eks_node_group.workers.resources[0].autoscaling_groups[0].name }
output "cas_role_arn" { value = aws_iam_role.cas.arn }
output "workload_role_arns" { value = { for key, role in aws_iam_role.workload : key => role.arn } }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.eks.arn }
output "rds_endpoint" { value = aws_db_instance.db.address }
output "rds_database_name" { value = aws_db_instance.db.db_name }
output "rds_master_secret_arn" {
  description = "ARN only, never the secret value. For restricted DB bootstrap, not API pods."
  value       = aws_db_instance.db.master_user_secret[0].secret_arn
}
output "application_db_secret_arn" {
  description = "Populate using the controlled DB bootstrap Job before deploying API."
  value       = aws_secretsmanager_secret.app_db.arn
}
output "acm_certificate_arn" { value = try(aws_acm_certificate_validation.api[0].certificate_arn, null) }
output "ssm_session_document_name" { value = aws_ssm_document.session_logging.name }
output "ssm_operator_policy_arn" { value = aws_iam_policy.ssm_operator.arn }

output "application_namespace" { value = var.application_namespace }
