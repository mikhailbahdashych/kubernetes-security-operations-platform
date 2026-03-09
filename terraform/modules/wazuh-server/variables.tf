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

variable "vpc_cidr" {
  description = "CIDR block of the VPC for agent communication rules"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the Wazuh server"
  type        = string
  default     = "t3.large"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the Wazuh server"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_dashboard_cidr" {
  description = "CIDR block allowed to access the Wazuh dashboard"
  type        = string
  default     = "0.0.0.0/0"
}
