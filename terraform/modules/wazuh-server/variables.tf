# =============================================================================
# Wazuh Server Module — Input Variables
# =============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_id" {
  description = "ID of the public subnet for the Wazuh server"
  type        = string
}

# Used in security group rules to restrict agent communication to VPC-internal
# traffic only — prevents external systems from impersonating agents
variable "vpc_cidr" {
  description = "CIDR block of the VPC for agent communication rules"
  type        = string
}

# t3.large (2 vCPU, 8 GiB) is the minimum for running Wazuh Manager +
# Indexer (OpenSearch) + Dashboard together. OpenSearch alone needs ~4 GiB.
variable "instance_type" {
  description = "EC2 instance type for the Wazuh server"
  type        = string
  default     = "t3.large"
}

# WARNING: Default 0.0.0.0/0 allows SSH from anywhere — restrict this to
# your IP or VPN CIDR in production
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the Wazuh server"
  type        = string
  default     = "0.0.0.0/0"
}

# WARNING: Default 0.0.0.0/0 exposes the dashboard publicly — restrict
# this to your IP or VPN CIDR in production
variable "allowed_dashboard_cidr" {
  description = "CIDR block allowed to access the Wazuh dashboard"
  type        = string
  default     = "0.0.0.0/0"
}
