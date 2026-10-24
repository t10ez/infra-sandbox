terraform {
  required_version = ">= 1.5"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

variable "endpoint" {
  description = "Floci endpoint used by Terraform. Empty string targets real AWS."
  type        = string
  default     = "http://localhost:4566"
}

variable "lambda_kms_endpoint" {
  description = "KMS/DynamoDB endpoint as seen from inside the Lambda container. Empty string targets real AWS."
  type        = string
  default     = "http://host.docker.internal:4566"
}

variable "region" {
  type    = string
  default = "ap-southeast-7"
}

locals {
  local_mode = var.endpoint != ""
  project    = "poc-kms-vault"
  tenants    = toset(["a", "b"])
}

provider "aws" {
  region = var.region

  access_key                  = local.local_mode ? "test" : null
  secret_key                  = local.local_mode ? "test" : null
  skip_credentials_validation = local.local_mode
  skip_metadata_api_check     = local.local_mode
  skip_requesting_account_id  = local.local_mode
  s3_use_path_style           = local.local_mode

  dynamic "endpoints" {
    for_each = local.local_mode ? [1] : []
    content {
      kms          = var.endpoint
      lambda       = var.endpoint
      apigatewayv2 = var.endpoint
      dynamodb     = var.endpoint
      iam          = var.endpoint
      sts          = var.endpoint
      logs         = var.endpoint
    }
  }

  default_tags {
    tags = { Project = local.project }
  }
}
