variable "project_name" { type = string }
variable "environment" { type = string }
variable "alert_email" { type = string }

variable "slack_webhook_url" {
  type      = string
  default   = ""
  sensitive = true
}
