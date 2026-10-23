variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project_name" {
  type    = string
  default = "poc-s3-guardduty"
}

variable "alert_email" {
  type        = string
  description = "Email to receive GuardDuty malware alerts"
  default     = ""
}
