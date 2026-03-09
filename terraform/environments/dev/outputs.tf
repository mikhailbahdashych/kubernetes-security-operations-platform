output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "eks_kubeconfig_command" {
  description = "AWS CLI command to update kubeconfig for cluster access"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "wazuh_public_ip" {
  description = "Public IP address of the Wazuh server"
  value       = var.deploy_wazuh ? module.wazuh[0].wazuh_public_ip : null
}

output "wazuh_private_ip" {
  description = "Private IP address of the Wazuh server"
  value       = var.deploy_wazuh ? module.wazuh[0].wazuh_private_ip : null
}

output "wazuh_dashboard_url" {
  description = "URL for the Wazuh dashboard"
  value       = var.deploy_wazuh ? module.wazuh[0].wazuh_dashboard_url : null
}

output "wazuh_instance_id" {
  description = "Instance ID of the Wazuh server"
  value       = var.deploy_wazuh ? module.wazuh[0].wazuh_instance_id : null
}
