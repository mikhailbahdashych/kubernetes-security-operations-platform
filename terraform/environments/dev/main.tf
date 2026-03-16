# =============================================================================
# Dev Environment — Root Module
#
# Orchestrates the three infrastructure modules (VPC, EKS, Wazuh) for the
# development environment. This is the entry point for `terraform apply`.
#
# Deployment order (handled automatically by Terraform dependency graph):
#   1. VPC  — network foundation
#   2. EKS  — Kubernetes cluster in private subnets
#   3. Wazuh — optional HIDS server in a public subnet
# =============================================================================

# AWS provider configuration with default tags applied to all resources
provider "aws" {
  region = var.region

  # These tags are automatically applied to every resource created by this
  # Terraform configuration — ensures consistent tagging for cost tracking
  # and resource identification
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Cluster name is derived from project + environment to avoid naming conflicts
# when running multiple environments (e.g., ksop-dev, ksop-staging)
locals {
  cluster_name = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# VPC — Network foundation with public/private subnets across 2 AZs
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  cluster_name = local.cluster_name
  environment  = var.environment
  vpc_cidr     = "10.0.0.0/16"
}

# -----------------------------------------------------------------------------
# EKS — Security-hardened Kubernetes cluster with spot nodes
# Depends on: VPC (needs vpc_id and private_subnet_ids)
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  cluster_version    = var.cluster_version
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  instance_types     = var.node_instance_types
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
}

# -----------------------------------------------------------------------------
# Wazuh Server — Optional HIDS on EC2 (opt-in via deploy_wazuh variable)
# Depends on: VPC (needs vpc_id and public_subnet_id)
# Set deploy_wazuh = true in terraform.tfvars to enable
# -----------------------------------------------------------------------------
module "wazuh" {
  source = "../../modules/wazuh-server"
  count  = var.deploy_wazuh ? 1 : 0

  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  public_subnet_id       = module.vpc.public_subnet_ids[0]
  vpc_cidr               = "10.0.0.0/16"
  allowed_ssh_cidr       = var.allowed_ssh_cidr
  allowed_dashboard_cidr = var.allowed_dashboard_cidr
}
