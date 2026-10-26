variable "aws_region" {
  description = "Region for every Task 1 resource."
  type        = string
  default     = "us-east-1"
}
variable "aws_account_id" {
  description = "Intended AWS account; the provider rejects another account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Supply your 12-digit AWS account ID."
  }
}
variable "project_name" {
  type    = string
  default = "cloud-engineer-onEks-assessment"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{2,34}$", var.project_name))
    error_message = "Use 3-35 letters, digits or hyphens, beginning with a letter."
  }
}
variable "environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Use dev or prod; this project deploys only one selected environment."
  }
}
variable "owner" {
  description = "Non-secret owner tag."
  type        = string
  default     = "Chinonso Ugwoh"
}
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Supply exactly two different available AZs in your chosen Region."
  }
}
variable "cluster_name" {
  type    = string
  default = "assessment-cluster"
}
variable "kubernetes_version" {
  description = "Explicit EKS minor version verified as supported in aws_region before planning."
  type        = string
  validation {
    condition     = can(regex("^1[.][0-9]+$", var.kubernetes_version))
    error_message = "Use a supported minor version in the form 1.NN."
  }
}
variable "eks_admin_principal_arn" {
  description = "Existing IAM role/user ARN for initial cluster administration; never an STS session ARN."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/.+$", var.eks_admin_principal_arn))
    error_message = "Supply an IAM role or user ARN."
  }
}
variable "public_api_access" {
  description = "Restricted public API for workstation access; private access stays enabled."
  type        = bool
  default     = true
}
variable "public_api_cidrs" {
  description = "Trusted public IPv4 egress CIDRs, normally your IP/32. No world-open API."
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([for cidr in var.public_api_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Use valid IPv4 CIDRs /24 or narrower, preferably /32."
  }
}
variable "private_api_client_security_groups" {
  description = "Optional stable label => SG ID for an admin/runner with VPC connectivity."
  type        = map(string)
  default     = {}
}
variable "node_instance_type" {
  description = "x86_64 instance type compatible with the selected AL2023_x86_64_STANDARD AMI."
  type        = string
  default     = "t3.medium"
}
variable "node_min_size" {
  type    = number
  default = 2
}
variable "node_desired_size" {
  type    = number
  default = 2
}
variable "node_max_size" {
  type    = number
  default = 4
}
variable "node_ami_release_version" {
  description = "Optional pinned EKS AL2023 AMI release; record the selected release after initial testing."
  type        = string
  default     = null
}
variable "addon_versions" {
  description = "Explicit versions validated for kubernetes_version using describe-addon-versions."
  type = object({
    vpc_cni    = string
    coredns    = string
    kube_proxy = string
  })
  validation {
    condition     = alltrue([for version in values(var.addon_versions) : can(regex("^v[0-9]+[.][0-9]+[.][0-9]+-eksbuild[.][0-9]+$", version))])
    error_message = "Pin each add-on to a verified vX.Y.Z-eksbuild.N version."
  }
}
variable "api_port" {
  type    = number
  default = 8080
  validation {
    condition     = var.api_port >= 1024 && var.api_port <= 65535 && floor(var.api_port) == var.api_port
    error_message = "Use an integer unprivileged API port between 1024 and 65535."
  }
}
variable "public_https_cidrs" {
  description = "ALB visitor IPv4 ranges, distinct from Kubernetes API access."
  type        = set(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = alltrue([for cidr in var.public_https_cidrs : can(cidrnetmask(cidr))])
    error_message = "Supply valid IPv4 CIDRs."
  }
}
variable "enable_http_redirect" {
  type    = bool
  default = true
}
variable "enable_ssm_endpoints" {
  description = "Optional private ssm/ssmmessages endpoints. NAT already provides access; endpoints add charges."
  type        = bool
  default     = false
}
variable "db_engine_version" {
  description = "Explicit supported PostgreSQL version, for example an available 16.x release. Verify in AWS."
  type        = string
  validation {
    condition     = can(regex("^[0-9]+[.][0-9]+$", var.db_engine_version))
    error_message = "Supply an available PostgreSQL major.minor version."
  }
}
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "db_multi_az" {
  description = "false retains the original cost-saving sandbox choice; true improves availability and costs more."
  type        = bool
  default     = false
}
variable "db_deletion_protection" {
  type    = bool
  default = true
}
variable "db_name" {
  type    = string
  default = "appdb"
}
variable "domain_name" {
  description = "Optional API DNS name in an existing Route53 public hosted zone. Supply together with hosted_zone_id."
  type        = string
  default     = null
}
variable "hosted_zone_id" {
  description = "Existing public Route53 hosted zone ID; no duplicate hosted zone is created."
  type        = string
  default     = null
}

variable "application_namespace" {
  description = "Namespace used by Task 4 API and migration service accounts."
  type        = string
  default     = "prod"
  validation {
    condition     = length(var.application_namespace) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.application_namespace))
    error_message = "Use a valid Kubernetes namespace name."
  }
}
