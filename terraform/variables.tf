variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-2"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID for us-east-2"
  type        = string
  default     = "ami-0ea3c35c5c3284d82" # Ubuntu 22.04 LTS in us-east-2
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
  # No default - must be provided
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "CA2-Swarm"
}
