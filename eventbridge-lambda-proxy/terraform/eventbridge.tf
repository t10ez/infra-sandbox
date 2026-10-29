# Every rule rewrites its event with input_transformer into one shape:
#   {"report_type": "...", "event_id": "...", "time": "...", "trigger": "..."}
# Placeholders are quoted ("<id>"): inside a JSON string both AWS and floci
# substitute the raw value. Unquoted <id> is auto-quoted by AWS but not floci.
# The EventBridge event id travels on as X-Idempotency-Key, so the target can
# drop duplicates (Lambda async delivery is at-least-once).

# ── Schedule: one rule per report type ────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "schedule" {
  for_each            = var.report_schedules
  name                = "${var.project_name}-schedule-${each.key}"
  description         = "Report ${each.key} on ${each.value}"
  schedule_expression = each.value
  state               = var.schedules_enabled ? "ENABLED" : "DISABLED"
}

resource "aws_cloudwatch_event_target" "schedule" {
  for_each  = var.report_schedules
  rule      = aws_cloudwatch_event_rule.schedule[each.key].name
  target_id = "proxy"
  arn       = aws_lambda_function.proxy.arn

  input_transformer {
    input_paths = {
      id   = "$.id"
      time = "$.time"
    }
    input_template = trimspace(<<-JSON
      {"report_type": "${each.key}", "event_id": "<id>", "time": "<time>", "trigger": "schedule"}
    JSON
    )
  }
}

resource "aws_lambda_permission" "schedule" {
  for_each      = var.report_schedules
  statement_id  = "AllowSchedule-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[each.key].arn
}

# ── On demand: put-events with detail.report_type ─────────────────────────────

resource "aws_cloudwatch_event_rule" "on_demand" {
  name        = "${var.project_name}-on-demand"
  description = "Report Requested events from ${var.event_source}"
  event_pattern = jsonencode({
    source        = [var.event_source]
    "detail-type" = ["Report Requested"]
    detail        = { report_type = local.report_list }
  })
}

resource "aws_cloudwatch_event_target" "on_demand" {
  rule      = aws_cloudwatch_event_rule.on_demand.name
  target_id = "proxy"
  arn       = aws_lambda_function.proxy.arn

  input_transformer {
    input_paths = {
      id          = "$.id"
      time        = "$.time"
      report_type = "$.detail.report_type"
    }
    input_template = trimspace(<<-JSON
      {"report_type": "<report_type>", "event_id": "<id>", "time": "<time>", "trigger": "on_demand"}
    JSON
    )
  }
}

resource "aws_lambda_permission" "on_demand" {
  statement_id  = "AllowOnDemand"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.on_demand.arn
}
