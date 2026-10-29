terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # floci (local emulator) when var.endpoint is set; real AWS otherwise.
  access_key                  = local.local_mode ? "test" : null
  secret_key                  = local.local_mode ? "test" : null
  skip_credentials_validation = local.local_mode
  skip_metadata_api_check     = local.local_mode
  skip_requesting_account_id  = local.local_mode

  dynamic "endpoints" {
    for_each = local.local_mode ? [1] : []
    content {
      lambda         = var.endpoint
      iam            = var.endpoint
      sts            = var.endpoint
      cloudwatchlogs = var.endpoint
      eventbridge    = var.endpoint
    }
  }

  default_tags {
    tags = { Project = var.project_name }
  }
}

locals {
  local_mode  = var.endpoint != ""
  build_dir   = "${path.module}/../build"
  use_echo    = var.target_url == ""
  target_url  = local.use_echo ? trimsuffix(aws_lambda_function_url.echo[0].function_url, "/") : var.target_url
  report_list = sort(keys(var.report_schedules))
}
