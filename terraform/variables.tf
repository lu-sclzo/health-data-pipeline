variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "health-pipeline"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "unique_suffix" {
  description = "Unique suffix for globally unique resource names"
  type        = string
}

variable "my_ip" {
  description = "Your public IP address for SSH access"
  type        = string
}
