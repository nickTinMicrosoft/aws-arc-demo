variable "aws_region" {
  description = "AWS region to deploy EC2 instances"
  type        = string
  default     = "us-east-1"
}

variable "instance_count" {
  description = "Number of SQL Server EC2 instances to create"
  type        = number
  default     = 5
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "sql_server_ami" {
  description = "AMI ID for Windows Server 2022 + SQL Server 2022 Express"
  type        = string
  default     = "ami-0ffa0f075391b705d" # us-east-1, May 2026
}

variable "admin_cidr" {
  description = "CIDR block allowed for RDP access (your IP/32)"
  type        = string
  default     = "0.0.0.0/0" # Restrict in production!
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for key pair"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "environment" {
  description = "Environment tag (dev, staging, production)"
  type        = string
  default     = "demo"
}

# Azure Arc variables
variable "azure_subscription_id" {
  description = "Azure subscription ID for Arc registration"
  type        = string
  sensitive   = true
}

variable "azure_resource_group" {
  description = "Azure resource group for Arc resources"
  type        = string
  default     = "arc-demo-rg"
}

variable "azure_tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  sensitive   = true
}

variable "azure_location" {
  description = "Azure region for Arc resources"
  type        = string
  default     = "eastus"
}

variable "azure_sp_app_id" {
  description = "Service principal app ID for Arc onboarding"
  type        = string
  sensitive   = true
}

variable "azure_sp_secret" {
  description = "Service principal secret for Arc onboarding"
  type        = string
  sensitive   = true
}
