# =============================================================================
# Provider Version Constraints
#
# Pinned with pessimistic constraints (~>) to allow patch/minor updates
# while preventing breaking major version changes.
# The TLS provider is required by the EKS module for OIDC/IRSA setup.
# =============================================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Used by the EKS module to fetch the OIDC provider's TLS certificate
    # for IRSA (IAM Roles for Service Accounts) trust relationship
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
