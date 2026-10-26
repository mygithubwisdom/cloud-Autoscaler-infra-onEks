# Entirely simulated providers: no AWS credentials, API calls or real resources.
mock_provider "aws" {
  # Provider validators still validate dependent arguments during a mock apply.
  # Supply realistic computed identifiers instead of generated random strings.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock-workload" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock-policy" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-alb-logs-bucket" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock-group" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock-app" }
  }
  mock_resource "aws_ssm_document" {
    defaults = { arn = "arn:aws:ssm:us-east-1:123456789012:document/mock-session" }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      identity = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK" }] }]
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      master_user_secret = [{
        secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock-master"
      }]
    }
  }
  mock_resource "aws_eks_node_group" {
    defaults = {
      resources = [{ autoscaling_groups = [{ name = "eks-mock-workers" }] }]
    }
  }
}
mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "0123456789012345678901234567890123456789" }]
    }
  }
}
mock_provider "random" {}
variables {
  aws_account_id          = "123456789012"
  eks_admin_principal_arn = "arn:aws:iam::123456789012:role/mock-administrator"
  kubernetes_version      = "1.34"
  public_api_cidrs        = ["203.0.113.1/32"]
  db_engine_version       = "16.8"
  addon_versions = {
    vpc_cni    = "v1.20.0-eksbuild.1"
    coredns    = "v1.12.0-eksbuild.1"
    kube_proxy = "v1.34.0-eksbuild.1"
  }
}
run "network_and_identity_baseline" {
  command = apply
  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2 && length(aws_subnet.database) == 2
    error_message = "Separate public, private worker and isolated DB subnets must span two AZs."
  }
  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_private_access && aws_eks_cluster.main.access_config[0].authentication_mode == "API"
    error_message = "Private endpoint and explicit access entries must be enabled."
  }
  assert {
    condition     = aws_eks_node_group.workers.launch_template[0].id == aws_launch_template.eks_nodes.id && contains(aws_launch_template.eks_nodes.vpc_security_group_ids, aws_security_group.eks_nodes.id)
    error_message = "Node SG must actually attach to the managed node group via its launch template."
  }
  assert {
    condition     = aws_launch_template.eks_nodes.metadata_options[0].http_tokens == "required" && aws_launch_template.eks_nodes.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Require IMDSv2 and limit ordinary pods' IMDS access."
  }
  assert {
    condition     = aws_db_instance.db.manage_master_user_password && aws_db_instance.db.storage_encrypted && !aws_db_instance.db.publicly_accessible && !aws_db_instance.db.skip_final_snapshot && aws_db_instance.db.deletion_protection
    error_message = "DB must be private, encrypted, managed-secret backed and protected against accidental deletion."
  }
  assert {
    condition     = aws_db_instance.db.db_subnet_group_name == aws_db_subnet_group.app.name && aws_vpc_security_group_ingress_rule.eks_to_rds.referenced_security_group_id == aws_security_group.eks_nodes.id && aws_vpc_security_group_ingress_rule.eks_to_rds.from_port == 5432
    error_message = "RDS must use the private DB subnet group and the actual worker-to-PostgreSQL path."
  }
  assert {
    condition     = length(aws_autoscaling_group_tag.cas) == 2 && jsondecode(aws_iam_role_policy.cas.policy).Statement[1].Condition.StringEquals["aws:ResourceTag/k8s.io/cluster-autoscaler/assessment-cluster"] == "owned"
    error_message = "CAS must discover the backing ASG and restrict scaling to the cluster tag."
  }
  assert {
    condition     = strcontains(aws_s3_bucket_policy.access_logs.policy, "/alb/AWSLogs/123456789012/*") && aws_s3_bucket_public_access_block.access_logs.block_public_policy
    error_message = "ALB log bucket must remain private and use the agreed account-scoped alb prefix."
  }
  assert {
    condition     = length(aws_vpc_endpoint.ssm) == 0 && length(aws_security_group.endpoints) == 0
    error_message = "NAT baseline must not create paid SSM endpoints by default."
  }
}
run "reject_world_open_cluster_api" {
  command = plan
  variables { public_api_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.public_api_cidrs]
}
run "reject_missing_cluster_api_allowlist" {
  command = plan
  variables { public_api_cidrs = [] }
  expect_failures = [aws_eks_cluster.main]
}
run "reject_invalid_node_bounds" {
  command = plan
  variables { node_max_size = 1 }
  expect_failures = [aws_eks_node_group.workers]
}
