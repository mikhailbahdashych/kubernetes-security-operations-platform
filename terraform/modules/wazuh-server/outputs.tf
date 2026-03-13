# =============================================================================
# Wazuh Server Module — Outputs
#
# The private IP is needed by the Wazuh agent DaemonSet ConfigMap
# (WAZUH_MANAGER_IP) so agents know where to send events.
# The public IP and dashboard URL are for operator access.
# =============================================================================

output "wazuh_public_ip" {
  description = "Public IP address of the Wazuh server"
  value       = aws_instance.wazuh.public_ip
}

# This IP should be set in kubernetes/manifests/wazuh-agents/wazuh-agent-config.yaml
# as the WAZUH_MANAGER_IP value
output "wazuh_private_ip" {
  description = "Private IP address of the Wazuh server"
  value       = aws_instance.wazuh.private_ip
}

output "wazuh_dashboard_url" {
  description = "URL for the Wazuh dashboard"
  value       = "https://${aws_instance.wazuh.public_ip}"
}

# Useful for SSM Session Manager access or instance management
output "wazuh_instance_id" {
  description = "Instance ID of the Wazuh server"
  value       = aws_instance.wazuh.id
}
