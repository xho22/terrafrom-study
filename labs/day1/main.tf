terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "environment" {
  type = string
}

locals {
  bucket_name = "terraform-sprint-${var.environment}-logs"
}

resource "aws_s3_bucket" "logs" {
  bucket = local.bucket_name

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.logs.bucket
}