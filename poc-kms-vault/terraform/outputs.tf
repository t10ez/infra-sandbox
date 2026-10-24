output "api_id" {
  value = aws_apigatewayv2_api.vault.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.vault.api_endpoint
}

output "lambda_function" {
  value = aws_lambda_function.vault.function_name
}

output "table" {
  value = aws_dynamodb_table.vault.name
}

output "key_ids" {
  value = {
    default  = aws_kms_key.default.key_id
    tenant_a = aws_kms_key.tenant["a"].key_id
    tenant_b = aws_kms_key.tenant["b"].key_id
    sign     = aws_kms_key.sign.key_id
  }
}
