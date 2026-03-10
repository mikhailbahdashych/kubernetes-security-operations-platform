provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  cluster_name = "${var.project_name}-${var.environment}"
}

module "vpc" {
  source = "../../modules/vpc"

  cluster_name = local.cluster_name
  environment  = var.environment
  vpc_cidr     = "10.0.0.0/16"
}

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
