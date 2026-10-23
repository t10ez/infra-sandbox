terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  bucket_src_name  = "${var.project_name}-src-${random_id.suffix.hex}"
  bucket_scan_name = "${var.project_name}-scan-${random_id.suffix.hex}"
}

# ── S3(a): Source bucket — user uploads here ───────────────────────────────────

resource "aws_s3_bucket" "source" {
  bucket        = local.bucket_src_name
  force_destroy = true
  tags          = { Project = var.project_name, Role = "source" }
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── S3(quarantine): Threats land here ─────────────────────────────────────────

resource "aws_s3_bucket" "quarantine" {
  bucket        = "${var.project_name}-quarantine-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Project = var.project_name, Role = "quarantine" }
}

resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket                  = aws_s3_bucket.quarantine.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── S3(approved): Clean files land here ────────────────────────────────────────

resource "aws_s3_bucket" "approved" {
  bucket        = "${var.project_name}-approved-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Project = var.project_name, Role = "approved" }
}

resource "aws_s3_bucket_versioning" "approved" {
  bucket = aws_s3_bucket.approved.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "approved" {
  bucket                  = aws_s3_bucket.approved.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── S3(b): Scan bucket — GuardDuty watches here ────────────────────────────────

resource "aws_s3_bucket" "scan" {
  bucket        = local.bucket_scan_name
  force_destroy = true
  tags          = { Project = var.project_name, Role = "scan" }
}

resource "aws_s3_bucket_versioning" "scan" {
  bucket = aws_s3_bucket.scan.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "scan" {
  bucket                  = aws_s3_bucket.scan.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "scan" {
  bucket      = aws_s3_bucket.scan.id
  eventbridge = true
}

# ── IAM: S3 Replication role ───────────────────────────────────────────────────

resource "aws_iam_role" "s3_replication" {
  name = "${var.project_name}-s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${var.project_name}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadSource"
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.source.arn
      },
      {
        Sid    = "AllowReadSourceObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
        ]
        Resource = "${aws_s3_bucket.source.arn}/*"
      },
      {
        Sid    = "AllowWriteDest"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
        ]
        Resource = "${aws_s3_bucket.scan.arn}/*"
      },
    ]
  })
}

# ── SRR: Source → Scan ─────────────────────────────────────────────────────────

resource "aws_s3_bucket_replication_configuration" "src_to_scan" {
  bucket = aws_s3_bucket.source.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.scan.arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.scan,
  ]
}

# ── IAM: GuardDuty Malware Protection role ─────────────────────────────────────

data "aws_iam_policy_document" "guardduty_malware_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["malware-protection-plan.guardduty.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:guardduty:${var.aws_region}:${local.account_id}:malware-protection-plan/*"]
    }
  }
}

resource "aws_iam_role" "guardduty_malware" {
  name               = "${var.project_name}-guardduty-malware-role"
  assume_role_policy = data.aws_iam_policy_document.guardduty_malware_assume.json
  tags               = { Project = var.project_name }
}

resource "aws_iam_role_policy" "guardduty_malware" {
  name = "${var.project_name}-guardduty-malware-policy"
  role = aws_iam_role.guardduty_malware.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowReadObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
        Resource = [aws_s3_bucket.scan.arn, "${aws_s3_bucket.scan.arn}/*"]
      },
      {
        Sid    = "AllowTagObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObjectTagging", "s3:GetObjectVersionTagging",
          "s3:PutObjectTagging", "s3:PutObjectVersionTagging",
        ]
        Resource = "${aws_s3_bucket.scan.arn}/*"
      },
      {
        Sid      = "AllowValidationObject"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.scan.arn}/malware-protection-resource-validation-object"
      },
      {
        Sid      = "AllowBucketNotification"
        Effect   = "Allow"
        Action   = ["s3:GetBucketNotification", "s3:PutBucketNotification"]
        Resource = aws_s3_bucket.scan.arn
      },
      {
        Sid    = "AllowEventBridgeManagedRule"
        Effect = "Allow"
        Action = [
          "events:PutRule", "events:PutTargets",
          "events:DeleteRule", "events:RemoveTargets",
          "events:DescribeRule", "events:ListTargetsByRule",
        ]
        Resource = "arn:aws:events:${var.aws_region}:${local.account_id}:rule/*"
      },
    ]
  })
}

# ── GuardDuty Detector + Malware Protection Plan ───────────────────────────────

resource "aws_guardduty_detector" "main" {
  enable = true
  tags   = { Project = var.project_name }
}

resource "aws_guardduty_malware_protection_plan" "main" {
  role = aws_iam_role.guardduty_malware.arn

  protected_resource {
    s3_bucket {
      bucket_name = aws_s3_bucket.scan.id
    }
  }

  actions {
    tagging { status = "ENABLED" }
  }

  tags       = { Project = var.project_name }
  depends_on = [aws_iam_role_policy.guardduty_malware]
}

# ── EventBridge: S3 Object Tags Added on scan bucket → Lambda ──────────────────
# Fires for every GuardDuty scan result (THREATS_FOUND, NO_THREATS_FOUND, etc.)
# Lambda calls GetObjectTagging to read the actual GuardDutyMalwareScanStatus value.

resource "aws_cloudwatch_event_rule" "s3_tags_added" {
  name        = "${var.project_name}-s3-tags-added"
  description = "S3 Object Tags Added on scan bucket → Lambda (all scan results)"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Tags Added"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.scan.id]
      }
    }
  })

  tags = { Project = var.project_name }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.s3_tags_added.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.scan_logger.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scan_logger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_tags_added.arn
}

# ── CloudWatch Log Group: all GuardDuty findings ──────────────────────────────

resource "aws_cloudwatch_event_rule" "all_guardduty" {
  name          = "${var.project_name}-all-findings"
  description   = "Log all GuardDuty findings"
  event_pattern = jsonencode({ source = ["aws.guardduty"], detail-type = ["GuardDuty Finding"] })
}

resource "aws_cloudwatch_log_group" "guardduty_findings" {
  name              = "/guardduty/${var.project_name}/findings"
  retention_in_days = 7
  tags              = { Project = var.project_name }
}

resource "aws_cloudwatch_event_target" "logs" {
  rule      = aws_cloudwatch_event_rule.all_guardduty.name
  target_id = "SendToLogs"
  arn       = aws_cloudwatch_log_group.guardduty_findings.arn
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_to_cw" {
  policy_name = "${var.project_name}-eventbridge-cw"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.guardduty_findings.arn}:*"
    }]
  })
}
