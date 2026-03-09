variable "project_name" {
  description = "Name of the project, used as prefix for resource names"
  type        = string
  default     = "ksop"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "List of EC2 instance types for EKS worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "deploy_wazuh" {
  description = "Whether to deploy the Wazuh server (opt-in)"
  type        = bool
  default     = false
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
