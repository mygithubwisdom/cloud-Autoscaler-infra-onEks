locals {
  name_prefix = "${lower(var.project_name)}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
  # Fixed a/b keys keep subnet addresses stable. Supply two AZs in aws_region.
  subnets = {
    a = { az = var.availability_zones[0], public = "10.0.1.0/24", private = "10.0.2.0/24", database = "10.0.5.0/24" }
    b = { az = var.availability_zones[1], public = "10.0.3.0/24", private = "10.0.4.0/24", database = "10.0.6.0/24" }
  }
  public_subnet_ids   = [for key in ["a", "b"] : aws_subnet.public[key].id]
  private_subnet_ids  = [for key in ["a", "b"] : aws_subnet.private[key].id]
  database_subnet_ids = [for key in ["a", "b"] : aws_subnet.database[key].id]
}
