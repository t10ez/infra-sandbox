output "source_bucket" {
  description = "Upload files HERE — SRR replicates to scan bucket"
  value       = aws_s3_bucket.source.id
}

output "scan_bucket" {
  description = "GuardDuty watches this bucket"
  value       = aws_s3_bucket.scan.id
}

output "quarantine_bucket" {
  description = "Threats moved here"
  value       = aws_s3_bucket.quarantine.id
}

output "approved_bucket" {
  description = "Clean files moved here"
  value       = aws_s3_bucket.approved.id
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "malware_protection_plan_id" {
  value = aws_guardduty_malware_protection_plan.main.id
}

output "lambda_function" {
  value = aws_lambda_function.scan_logger.function_name
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}

output "test_commands" {
  value = <<-EOT
    # 1. Upload EICAR to SOURCE bucket (SRR replicates to scan bucket)
    ../scripts/upload_test.sh ${aws_s3_bucket.source.id}

    # 2. Check replication to scan bucket (~few seconds)
    aws s3 ls s3://${aws_s3_bucket.scan.id} --region ${var.aws_region}

    # 3. Check scan tag on scan bucket object
    aws s3api get-object-tagging \
      --bucket ${aws_s3_bucket.scan.id} \
      --key eicar_test.txt --region ${var.aws_region}

    # 4. Watch Lambda logs for findings
    aws logs tail ${aws_cloudwatch_log_group.lambda.name} --follow --region ${var.aws_region}
  EOT
}
