output "key_ids" {
  value = {
    default  = aws_kms_key.default.key_id
    tenant_a = aws_kms_key.tenant["a"].key_id
    tenant_b = aws_kms_key.tenant["b"].key_id
    sign     = aws_kms_key.sign.key_id
  }
}
