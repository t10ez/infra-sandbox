data "aws_caller_identity" "current" {}

# Key policy: account root administers; use of the keys is granted through IAM (lambda.tf).
data "aws_iam_policy_document" "key" {
  statement {
    sid       = "RootAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "default" {
  description             = "${local.project} default data key"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "default" {
  name          = "alias/vault-data"
  target_key_id = aws_kms_key.default.key_id
}

resource "aws_kms_key" "tenant" {
  for_each                = local.tenants
  description             = "${local.project} tenant ${each.key} data key"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "tenant" {
  for_each      = local.tenants
  name          = "alias/vault-tenant-${each.key}"
  target_key_id = aws_kms_key.tenant[each.key].key_id
}

resource "aws_kms_key" "sign" {
  description              = "${local.project} signing key"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  policy                   = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "sign" {
  name          = "alias/vault-sign"
  target_key_id = aws_kms_key.sign.key_id
}
