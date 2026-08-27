mock_provider "aws" {}

run "uses_the_environment_in_the_bucket_name" {
  variables {
    environment = "dev"
  }

  assert {
    condition     = aws_s3_bucket.logs.bucket == "terraform-sprint-dev-logs"
    error_message = "bucket 名称必须包含环境"
  }
}

run "adds_required_tags" {
  variables {
    environment = "dev"
  }

  assert {
    condition     = aws_s3_bucket.logs.tags.ManagedBy == "Terraform"
    error_message = "所有资源都必须标注 ManagedBy=Terraform"
  }
}