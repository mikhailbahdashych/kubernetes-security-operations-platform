output "wazuh_public_ip" {
  description = "Public IP address of the Wazuh server"
  value       = aws_instance.wazuh.public_ip
}

output "wazuh_private_ip" {
  description = "Private IP address of the Wazuh server"
  value       = aws_instance.wazuh.private_ip
}

output "wazuh_dashboard_url" {
  description = "URL for the Wazuh dashboard"
  value       = "https://${aws_instance.wazuh.public_ip}"
}

output "wazuh_instance_id" {
  description = "Instance ID of the Wazuh server"
  value       = aws_instance.wazuh.id
}
