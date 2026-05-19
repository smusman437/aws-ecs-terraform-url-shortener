variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used in resource tags and names"
  type        = string
  default     = "url-shortener"
}

variable "environment" {
  description = "Environment label (dev, prod)"
  type        = string
  default     = "dev"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "url-shortener"
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1
}

variable "enable_autoscaling" {
  description = "Enable CPU-based auto-scaling on the ECS service"
  type        = bool
  default     = false
}

variable "autoscaling_min" {
  description = "Minimum task count when auto-scaling is enabled"
  type        = number
  default     = 2
}

variable "autoscaling_max" {
  description = "Maximum task count when auto-scaling is enabled"
  type        = number
  default     = 10
}
