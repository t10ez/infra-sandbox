data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault" {
  name               = "${local.project}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Least privilege: data keys may GenerateDataKey/Decrypt/ReEncrypt, the signing key may only Sign/Verify.
data "aws_iam_policy_document" "vault" {
  statement {
    sid     = "DataKeys"
    actions = ["kms:GenerateDataKey", "kms:Decrypt", "kms:ReEncryptFrom", "kms:ReEncryptTo"]
    resources = concat(
      [aws_kms_key.default.arn],
      [for k in aws_kms_key.tenant : k.arn],
    )
  }
  statement {
    sid       = "SigningKey"
    actions   = ["kms:Sign", "kms:Verify"]
    resources = [aws_kms_key.sign.arn]
  }
  statement {
    sid       = "Records"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.vault.arn]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vault" {
  name   = "vault"
  role   = aws_iam_role.vault.id
  policy = data.aws_iam_policy_document.vault.json
}

# scripts/build.sh creates build/ (handler.py + cryptography wheel for the Lambda architecture).
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../build"
  output_path = "${path.module}/../build.zip"
}

resource "aws_lambda_function" "vault" {
  function_name    = "${local.project}-api"
  role             = aws_iam_role.vault.arn
  runtime          = "python3.12"
  architectures    = [var.lambda_arch]
  handler          = "handler.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = merge(
      {
        TABLE         = aws_dynamodb_table.vault.name
        SIGN_KEY      = aws_kms_alias.sign.name
        DEFAULT_KEY   = aws_kms_alias.default.name
        TENANT_PREFIX = "alias/vault-tenant-"
      },
      var.lambda_kms_endpoint == "" ? {} : { AWS_ENDPOINT_URL = var.lambda_kms_endpoint },
    )
  }
}

variable "lambda_arch" {
  type    = string
  default = "arm64"
}
