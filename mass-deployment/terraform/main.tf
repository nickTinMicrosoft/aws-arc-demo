# Terraform: EC2 Fleet with Auto Arc Onboarding
#
# This creates multiple EC2 instances that automatically onboard to Azure Arc
# on first boot via user data script.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Security Group - RDP + outbound for Arc
resource "aws_security_group" "arc_demo" {
  name        = "arc-fleet-sg"
  description = "Security group for Arc-managed SQL Server fleet"

  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "All outbound (required for Arc agent)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "arc-fleet-sg"
    Purpose = "Azure-Arc-Demo"
  }
}

# Key Pair
resource "aws_key_pair" "arc_fleet" {
  key_name   = "arc-fleet-key"
  public_key = file(var.ssh_public_key_path)
}

# EC2 Instances - SQL Server fleet
resource "aws_instance" "sql_server" {
  count = var.instance_count

  ami           = var.sql_server_ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.arc_fleet.key_name

  vpc_security_group_ids = [aws_security_group.arc_demo.id]

  root_block_device {
    volume_size = 80
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.ps1", {
    subscription_id = var.azure_subscription_id
    resource_group  = var.azure_resource_group
    tenant_id       = var.azure_tenant_id
    location        = var.azure_location
    sp_app_id       = var.azure_sp_app_id
    sp_secret       = var.azure_sp_secret
  })

  tags = {
    Name        = "ArcSQL-${format("%02d", count.index + 1)}"
    Purpose     = "Azure-Arc-Demo"
    ArcOnboard  = "true"
    Environment = var.environment
  }
}

# Outputs
output "instance_ids" {
  value = aws_instance.sql_server[*].id
}

output "public_ips" {
  value = aws_instance.sql_server[*].public_ip
}

output "instance_names" {
  value = aws_instance.sql_server[*].tags.Name
}
