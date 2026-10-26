output "state_bucket_name" {
  description = "S3 bucket to place in the production backend configuration."
  value       = aws_s3_bucket.terraform_state.id
}

output "backend_configuration" {
  description = "Values to copy into task-1/infra/backend.prod.hcl."
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "task1-assessment/prod/terraform.tfstate"
    region         = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
