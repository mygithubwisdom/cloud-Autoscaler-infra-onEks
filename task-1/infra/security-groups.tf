resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.main-webapp.id


  # Allow DB access from app servers only
  ingress {
    description     = "DB access from app servers"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_server.id]
  }


  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main-webapp.cidr_block]
  }


  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = var.environment
  }
}

 #SECURITY GROUPS (The State-aware "Locks")
# ==========================================================

# --- ALB Security Group (Public Facing) ---
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main-webapp.id

  ingress {
    description = "Public HTTPS Access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Allow ALB to send traffic to App Servers on the Node Port
  egress {
    description = "Forward traffic to app servers"
    from_port   = var.node_app_port
    to_port     = var.node_app_port
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main-webapp.cidr_block]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
  }
}

# --- App Server Security Group (Private) ---
resource "aws_security_group" "app_server" {
  name        = "${var.project_name}-app-sg-prod"
  description = "Production Security Group for Express App - Private Subnet"
  vpc_id      = aws_vpc.main-webapp.id

  # Inbound: ONLY Web traffic from the ALB
  ingress {
    description     = "Node.js app port from ALB"
    from_port       = var.node_app_port
    to_port         = var.node_app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] 
  }

  # Outbound: HTTPS (Required for SSM, OS updates, and API calls)
  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Database (To RDS in Private Subnet)
  egress {
    description = "Allow traffic to RDS"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main-webapp.cidr_block]
  }

  tags = {
    Name        = "${var.project_name}-app-sg-prod"
    Environment = var.environment
  }
}

#Eks of security groups

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.name_prefix}-nodes-"
  description = "Private EKS worker ENIs and ordinary VPC CNI pods"
  vpc_id      = var.vpc_id
  tags = merge(var.tags, {
    Name                                        = "${var.name_prefix}-nodes"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Public HTTPS frontend; backend only to API port"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}
resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "Private PostgreSQL accepts only EKS workers"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-rds" })
}
resource "aws_security_group" "endpoints" {
  count       = var.create_endpoint_security_group ? 1 : 0
  name_prefix = "${var.name_prefix}-endpoints-"
  description = "Optional AWS interface endpoints accessed by EKS workers"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-endpoints" })
}
 
# Client -> load balancer. An SG does not create a listener or certificate.
resource "aws_vpc_security_group_ingress_rule" "https_to_alb" {
  for_each          = var.public_https_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS visitors"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_ingress_rule" "http_redirect_to_alb" {
  for_each          = var.enable_http_redirect ? var.public_https_cidrs : toset([])
  security_group_id = aws_security_group.alb.id
  description       = "HTTP redirect listener only"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

# Deliberate permissive INTERNAL baseline: DNS, pod traffic, metrics-server,
# Prometheus, kubelets and operators. Enforce pod microsegmentation separately.
resource "aws_vpc_security_group_ingress_rule" "node_internal" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  description                 = "Internal node and ordinary pod communication"
  ip_protocol                 = "-1"
}

# Deliberate sandbox tradeoff: broad outbound prevents bootstrap/image/API
# failures. Private nodes still require NAT or the appropriate VPC endpoints.
# This is NOT least-privilege egress. Harden after inventorying actual traffic.
resource "aws_vpc_security_group_egress_rule" "node_outbound" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Documented dev baseline outbound access"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# SGs are stateful: PostgreSQL and endpoint replies need no egress rule.
resource "aws_vpc_security_group_ingress_rule" "nodes_to_endpoints" {
  count                       = var.create_endpoint_security_group ? 1 : 0
  security_group_id            = aws_security_group.endpoints[0].id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  description                 = "HTTPS to optional AWS interface endpoints"
  ip_protocol                 = "tcp"
  from_port                   = 443
  to_port                     = 443
}

# An optional VPC-connected runner can call the private Kubernetes API.
resource "aws_vpc_security_group_ingress_rule" "private_api_clients" {
  for_each                    = var.private_api_client_security_groups
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = each.value
  description                 = "Private API access for ${each.key}"
  ip_protocol                 = "tcp"
  from_port                   = 443
  to_port                     = 443
}

