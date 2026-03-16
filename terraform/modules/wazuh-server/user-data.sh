#!/bin/bash
# =============================================================================
# Wazuh Server — EC2 User Data (Cloud-Init) Script
#
# Runs once on first boot to bootstrap the Wazuh stack:
#   1. Updates system packages for latest security patches
#   2. Installs Docker and the Compose plugin
#   3. Writes the docker-compose.yml (injected via Terraform templatefile)
#   4. Tunes kernel parameters for OpenSearch
#   5. Starts the full Wazuh stack (Indexer + Manager + Dashboard)
#
# The docker_compose_content variable is injected by Terraform from the
# docker-compose.yml file in this module directory.
# =============================================================================
set -euxo pipefail

# Update system packages to apply latest security patches
dnf update -y

# Install Docker engine from the AL2023 package repository
dnf install -y docker
systemctl enable docker
systemctl start docker

# Install the Docker Compose plugin (v2) — fetches the latest release
# from GitHub. The $$ escaping is required because this file is processed
# by Terraform's templatefile() function.
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -SL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Create the directory where the Wazuh stack will run
mkdir -p /opt/wazuh

# Write the docker-compose.yml — content is injected by Terraform
cat > /opt/wazuh/docker-compose.yml << 'COMPOSE_EOF'
${docker_compose_content}
COMPOSE_EOF

# OpenSearch requires vm.max_map_count >= 262144 for memory-mapped files.
# Without this, the Wazuh Indexer container will fail to start.
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Start the Wazuh stack — services will auto-restart on failure (restart: always)
cd /opt/wazuh
docker compose up -d
