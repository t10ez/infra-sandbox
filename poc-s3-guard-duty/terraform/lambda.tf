data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../scripts/lambda_handler.py"
  output_path = "${path.module}/../scripts/lambda_handler.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.project_name}-lambda-s3"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadScanBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:GetObjectVersion",
          "s3:GetObjectTagging", "s3:GetObjectVersionTagging",
          "s3:DeleteObject", "s3:DeleteObjectVersion",
        ]
        Resource = "${aws_s3_bucket.scan.arn}/*"
      },
      {
        Sid      = "WriteDestBuckets"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:PutObjectTagging"]
        Resource = [
          "${aws_s3_bucket.quarantine.arn}/*",
          "${aws_s3_bucket.approved.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-scan-logger"
  retention_in_days = 7
  tags              = { Project = var.project_name }
}

resource "aws_lambda_function" "scan_logger" {
  function_name    = "${var.project_name}-scan-logger"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "lambda_handler.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 300

  environment {
    variables = {
      PROJECT          = var.project_name
      QUARANTINE_BUCKET = aws_s3_bucket.quarantine.id
      APPROVED_BUCKET   = aws_s3_bucket.approved.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = { Project = var.project_name }
}
