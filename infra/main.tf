terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment after creating the S3 bucket and DynamoDB table (see ROADMAP.md Phase 5b).
  # backend "s3" {
  #   bucket         = "url-shortener-terraform-state"
  #   key            = "url-shortener/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "url_shortener" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true # allow terraform destroy when images still exist in ECR

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}

module "ecs" {
  source = "./modules/ecs"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_id               = module.networking.vpc_id
  public_subnet_ids    = module.networking.public_subnet_ids
  ecr_repository_url   = aws_ecr_repository.url_shortener.repository_url
  desired_count        = var.desired_count
  enable_autoscaling   = var.enable_autoscaling
  autoscaling_min      = var.autoscaling_min
  autoscaling_max      = var.autoscaling_max
}

output "ecr_uri" {
  value       = aws_ecr_repository.url_shortener.repository_url
  description = "ECR repository URL — use this to tag and push your Docker image"
}

output "api_url" {
  value       = module.ecs.api_url
  description = "Public URL of your URL Shortener API"
}
