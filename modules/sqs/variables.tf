# SQS Module Variables
variable "name_prefix" { type = string }

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  type    = number
  default = 345600
}

variable "enable_dlq" {
  type    = bool
  default = true
}

variable "max_receive_count" {
  type    = number
  default = 5
}
