# =============================================================================
# VPC Module — Input Variables
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster, used for subnet discovery tags"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# The /16 CIDR provides 65,536 IPs — enough room for EKS pods using the
# VPC CNI plugin, which allocates one VPC IP per pod.
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
