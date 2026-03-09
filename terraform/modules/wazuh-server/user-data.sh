#!/bin/bash
set -euxo pipefail

# Update system packages
dnf update -y

# Install Docker
dnf install -y docker
systemctl enable docker
systemctl start docker

# Install Docker Compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -SL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Create Wazuh directory
mkdir -p /opt/wazuh

# Write docker-compose.yml
cat > /opt/wazuh/docker-compose.yml << 'COMPOSE_EOF'
${docker_compose_content}
COMPOSE_EOF

# Increase max_map_count for Wazuh Indexer (OpenSearch)
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# Start Wazuh stack
cd /opt/wazuh
docker compose up -d
