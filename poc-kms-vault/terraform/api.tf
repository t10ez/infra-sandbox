resource "aws_apigatewayv2_api" "vault" {
  name          = "${local.project}-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "vault" {
  api_id                 = aws_apigatewayv2_api.vault.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.vault.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "vault" {
  for_each  = toset(["POST /encrypt", "POST /decrypt", "POST /rotate/{id}", "POST /sign", "POST /verify"])
  api_id    = aws_apigatewayv2_api.vault.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.vault.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.vault.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vault.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.vault.execution_arn}/*/*"
}
