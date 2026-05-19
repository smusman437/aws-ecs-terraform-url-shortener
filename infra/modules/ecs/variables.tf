variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "ecr_repository_url" {
  type = string
}

variable "desired_count" {
  type = number
}

variable "enable_autoscaling" {
  type    = bool
  default = false
}

variable "autoscaling_min" {
  type    = number
  default = 2
}

variable "autoscaling_max" {
  type    = number
  default = 10
}
