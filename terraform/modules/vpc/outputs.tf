# =============================================================================
# VPC Module — Outputs
#
# Consumed by the EKS module (vpc_id, private_subnet_ids) and the Wazuh
# module (vpc_id, public_subnet_ids). The NAT gateway IP is exposed for
# allowlisting outbound cluster traffic in external firewalls.
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

# EKS worker nodes are placed in private subnets for security
output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

# Public subnets host load balancers and the optional Wazuh EC2 instance
output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

# Useful for allowlisting cluster egress in third-party services
output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway"
  value       = module.vpc.nat_public_ips[0]
}
