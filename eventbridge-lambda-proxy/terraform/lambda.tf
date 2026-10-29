# ── Proxy Lambda: Go + Gin, invoked by EventBridge ────────────────────────────

data "archive_file" "proxy" {
  type        = "zip"
  source_file = "${local.build_dir}/proxy/bootstrap"
  output_path = "${local.build_dir}/proxy.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "${var.project_name}-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "proxy_logs" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/aws/lambda/${var.project_name}-proxy"
  retention_in_days = 7
}

resource "aws_lambda_function" "proxy" {
  function_name    = "${var.project_name}-proxy"
  role             = aws_iam_role.proxy.arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "bootstrap"
  filename         = data.archive_file.proxy.output_path
  source_code_hash = data.archive_file.proxy.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      TARGET_URL     = local.target_url
      TARGET_TIMEOUT = var.target_timeout
      REPORT_TYPES   = join(",", local.report_list)
    }
  }

  depends_on = [aws_iam_role_policy_attachment.proxy_logs, aws_cloudwatch_log_group.proxy]
}

# EventBridge invokes Lambda asynchronously. An error from the handler means
# "retry"; after the last attempt the event is dropped (no DLQ in this POC).
resource "aws_lambda_function_event_invoke_config" "proxy" {
  function_name                = aws_lambda_function.proxy.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

# ── Echo Lambda: stand-in target, only when target_url is empty ───────────────
# Its Function URL is public (authorization_type NONE). It only echoes, and
# terraform destroy removes it.

data "archive_file" "echo" {
  count       = local.use_echo ? 1 : 0
  type        = "zip"
  source_file = "${local.build_dir}/echo/bootstrap"
  output_path = "${local.build_dir}/echo.zip"
}

resource "aws_iam_role" "echo" {
  count              = local.use_echo ? 1 : 0
  name               = "${var.project_name}-echo-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "echo_logs" {
  count      = local.use_echo ? 1 : 0
  role       = aws_iam_role.echo[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "echo" {
  count             = local.use_echo ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-echo"
  retention_in_days = 7
}

resource "aws_lambda_function" "echo" {
  count            = local.use_echo ? 1 : 0
  function_name    = "${var.project_name}-echo"
  role             = aws_iam_role.echo[0].arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "bootstrap"
  filename         = data.archive_file.echo[0].output_path
  source_code_hash = data.archive_file.echo[0].output_base64sha256
  memory_size      = 128
  timeout          = 10

  depends_on = [aws_iam_role_policy_attachment.echo_logs, aws_cloudwatch_log_group.echo]
}

resource "aws_lambda_function_url" "echo" {
  count              = local.use_echo ? 1 : 0
  function_name      = aws_lambda_function.echo[0].function_name
  authorization_type = "NONE"
}
