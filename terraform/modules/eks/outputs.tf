# =============================================================================
# EKS Module — Outputs
#
# These values are consumed by the dev environment root module and are
# needed for kubeconfig setup, IRSA configuration, and network policy
# integration with the Wazuh server.
# =============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

# Used by CI/CD and external tools to verify the cluster's TLS certificate
output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster CA"
  value       = module.eks.cluster_certificate_authority_data
}

# The cluster-level security group — controls traffic to/from the API server
output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

# The node security group — useful for adding rules that allow Wazuh
# agent traffic or other node-level communication
output "node_security_group_id" {
  description = "Security group ID attached to the EKS worker nodes"
  value       = module.eks.node_security_group_id
}

# Required for creating IRSA trust policies that map K8s ServiceAccounts
# to IAM roles
output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = module.eks.cluster_oidc_issuer_url
}
