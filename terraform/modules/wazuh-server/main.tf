# =============================================================================
# Wazuh Server Module — Host-based Intrusion Detection System (HIDS)
#
# Deploys a standalone Wazuh stack (Manager + Indexer + Dashboard) on an EC2
# spot instance using Docker Compose. This server receives events from Wazuh
# agents running as a DaemonSet on EKS nodes.
#
# Architecture:  EKS Nodes (Wazuh Agent) --TCP/1514--> EC2 (Wazuh Manager)
#                Browser --------HTTPS/443-----------> EC2 (Wazuh Dashboard)
#
# This module is opt-in: controlled by the `deploy_wazuh` variable in the
# dev environment.
# =============================================================================

# -----------------------------------------------------------------------------
# AMI lookup — always uses the latest Amazon Linux 2023 for patched base image
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# -----------------------------------------------------------------------------
# Security Group — restricts inbound access to only required ports
# -----------------------------------------------------------------------------
resource "aws_security_group" "wazuh" {
  name_prefix = "wazuh-${var.environment}-"
  description = "Security group for Wazuh server"
  vpc_id      = var.vpc_id

  # Wazuh Dashboard — exposed via HTTPS for browser access.
  # In production, restrict allowed_dashboard_cidr to a VPN or office IP range.
  ingress {
    description = "Wazuh Dashboard"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_dashboard_cidr]
  }

  # Wazuh agent event ingestion (TCP) — port 1514 for event data, 1515 for
  # agent registration/enrollment. Only accessible from within the VPC so
  # that only EKS nodes can communicate with the manager.
  ingress {
    description = "Wazuh agent communication (TCP)"
    from_port   = 1514
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Wazuh agent communication (UDP) — some agents use UDP for syslog-style
  # event forwarding
  ingress {
    description = "Wazuh agent communication (UDP)"
    from_port   = 1514
    to_port     = 1514
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # SSH access for debugging — should be restricted to a bastion or VPN
  # CIDR in production
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Egress: allow all outbound so the server can pull Docker images and
  # download threat intelligence updates
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wazuh-${var.environment}"
    Environment = var.environment
  }

  # Create the replacement SG before destroying the old one to avoid
  # downtime during security group changes
  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance — runs the Wazuh Docker Compose stack
# -----------------------------------------------------------------------------
resource "aws_instance" "wazuh" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  # Public subnet so the dashboard is reachable from the internet
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.wazuh.id]
  associate_public_ip_address = true

  # Spot instance for cost savings (~60-70% discount) — acceptable for
  # non-production HIDS. Spot interruptions will stop event collection
  # until the instance is relaunched.
  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  # 50 GB gp3 volume for Wazuh Indexer (OpenSearch) data, logs, and
  # agent registration database. Encrypted at rest with the default
  # AWS-managed EBS key.
  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # user-data.sh installs Docker, writes docker-compose.yml, and starts
  # the Wazuh stack on first boot
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    docker_compose_content = file("${path.module}/docker-compose.yml")
  }))

  tags = {
    Name        = "wazuh-${var.environment}"
    Environment = var.environment
  }
}
