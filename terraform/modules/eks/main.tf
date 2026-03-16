# =============================================================================
# EKS Module — Security-hardened Kubernetes cluster
#
# Provisions an EKS v1.31 cluster with:
#   - KMS envelope encryption for Kubernetes Secrets at rest
#   - All 5 control plane log types enabled for audit trail
#   - VPC CNI with native NetworkPolicy support (no Calico needed)
#   - Spot instances for cost optimization in dev
#   - IRSA (IAM Roles for Service Accounts) for fine-grained pod IAM
# =============================================================================

# -----------------------------------------------------------------------------
# KMS key for encrypting Kubernetes Secrets at rest (envelope encryption).
# This ensures etcd data is encrypted with a customer-managed key rather than
# the default AWS-managed key, satisfying compliance requirements.
# -----------------------------------------------------------------------------
resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secrets envelope encryption"
  deletion_window_in_days = 7
  # Automatic annual key rotation — required by most security frameworks
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

# Human-readable alias for the KMS key (visible in the AWS console)
resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Public access allows kubectl from developer machines; private access
  # lets worker nodes communicate with the API server within the VPC.
  # In production, consider restricting public access to specific CIDRs.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # IRSA lets pods assume IAM roles via OIDC — avoids sharing node-level
  # IAM credentials across all pods on a node
  enable_irsa = true

  # Enable ALL control plane log types for full audit coverage.
  # Logs go to CloudWatch Logs — essential for security incident investigation.
  cluster_enabled_log_types = [
    "api",              # API server request/response audit
    "audit",            # Kubernetes audit log (who did what)
    "authenticator",    # IAM authentication events
    "controllerManager", # Controller manager operations
    "scheduler",        # Pod scheduling decisions
  ]

  # Use our customer-managed KMS key instead of creating a new one
  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks_secrets.arn
    resources        = ["secrets"]  # Encrypt only Secrets (the only supported resource type)
  }

  cluster_addons = {
    # VPC CNI — assigns real VPC IPs to pods for native AWS networking.
    # enableNetworkPolicy activates the built-in NetworkPolicy controller,
    # eliminating the need for a third-party CNI like Calico.
    # before_compute = true ensures CNI is ready before nodes join.
    aws-vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    # CoreDNS — cluster-internal DNS resolution for service discovery
    coredns = {
      most_recent = true
    }
    # kube-proxy — manages iptables rules for Service routing on each node
    kube-proxy = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    security-workers = {
      name           = "security-workers"
      instance_types = var.instance_types
      # SPOT instances reduce compute costs by ~60-70% vs on-demand.
      # Acceptable for dev/learning; for production, use ON_DEMAND or mixed.
      capacity_type  = "SPOT"

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      labels = {
        role        = "security-worker"
        environment = var.environment
      }
    }
  }

  # Grants the IAM principal that creates the cluster full admin access
  # via an access entry (no aws-auth ConfigMap needed)
  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}
