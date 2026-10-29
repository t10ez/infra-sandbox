output "proxy_function" {
  value = aws_lambda_function.proxy.function_name
}

output "target_url" {
  value = local.target_url
}

output "schedule_rules" {
  value = { for k, r in aws_cloudwatch_event_rule.schedule : k => r.name }
}

output "test_commands" {
  value = <<-EOT
    # On-demand trigger
    ../scripts/trigger.sh a ${var.aws_region}

    # Proxy logs (forwarded / dropped / errors, plus REPORT lines with duration)
    aws logs tail ${aws_cloudwatch_log_group.proxy.name} --follow --region ${var.aws_region}
    %{if local.use_echo}
    # Target logs (what arrived, delivery_ms from event time)
    aws logs tail ${aws_cloudwatch_log_group.echo[0].name} --follow --region ${var.aws_region}
    %{endif}
  EOT
}
