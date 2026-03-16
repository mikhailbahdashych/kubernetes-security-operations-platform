# =============================================================================
# Dev Environment — Variable Values
#
# These override the defaults in variables.tf for the development deployment.
# To enable the Wazuh HIDS server, set deploy_wazuh = true.
# =============================================================================

project_name = "ksop"
environment  = "dev"
region       = "eu-central-1"

# Set to true to provision the Wazuh EC2 instance (~$50/month additional cost).
# After enabling, update kubernetes/manifests/wazuh-agents/wazuh-agent-config.yaml
# with the Wazuh server's private IP from terraform output.
deploy_wazuh = false
