# =============================================================================
# VPC Module — Network foundation for the EKS cluster
#
# Creates a production-style VPC with public and private subnets across two
# Availability Zones in eu-central-1. EKS worker nodes run in private subnets
# and reach the internet through a single NAT Gateway (cost-optimized for dev).
# Public subnets are used for load balancers and the optional Wazuh server.
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # Two AZs for high availability; EKS requires subnets in at least 2 AZs
  azs             = ["eu-central-1a", "eu-central-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  # Single NAT GW keeps costs low in dev — trade-off: single AZ is a SPOF.
  # For production, set single_nat_gateway = false to get one NAT GW per AZ.
  enable_nat_gateway   = true
  single_nat_gateway   = true

  # DNS settings required for EKS service discovery and IRSA OIDC resolution
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required by the AWS Load Balancer Controller for auto-discovering
  # which subnets to place internet-facing ALBs/NLBs in
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  # Tags for internal load balancers (e.g., internal services, Prometheus)
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}
