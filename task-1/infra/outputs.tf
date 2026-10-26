output "access_logs_bucket_name" {
  description = "S3 bucket name for ALB access logs"
  value       = aws_s3_bucket.access_logs.bucket
}

output "eks_node_security_group_id" {
  value = aws_security_group.eks_nodes.id
}
output "alb_security_group_id" {
  value = aws_security_group.alb.id
}
output "rds_security_group_id" {
  value = aws_security_group.rds.id
}
output "endpoint_security_group_id" {
  value = try(aws_security_group.endpoints[0].id, null)
}