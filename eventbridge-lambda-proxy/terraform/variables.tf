variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project_name" {
  type    = string
  default = "poc-eb-lambda-proxy"
}

variable "report_schedules" {
  type        = map(string)
  description = "Report type => EventBridge schedule expression. The keys are also the proxy's allowlist."
  default = {
    a = "rate(5 minutes)"
    b = "rate(10 minutes)"
  }
}

variable "schedules_enabled" {
  type        = bool
  description = "false keeps the schedule rules but disables them; on-demand events still work"
  default     = true
}

variable "target_url" {
  type        = string
  description = "Base URL the proxy forwards to as POST <target_url>/reports/<type>. Empty deploys the echo Lambda and uses its Function URL"
  default     = ""
}

variable "target_timeout" {
  type    = string
  default = "10s"
}

variable "event_source" {
  type        = string
  description = "Source of on-demand events sent with scripts/trigger.sh"
  default     = "poc.reports"
}

variable "endpoint" {
  type        = string
  description = "AWS endpoint override, e.g. http://localhost:4566 for floci. Empty = real AWS"
  default     = ""
}
