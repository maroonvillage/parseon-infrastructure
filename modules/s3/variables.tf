# S3 Module Variables
variable "name_prefix" { type = string }

variable "enable_versioning" {
  type    = bool
  default = true
}

variable "lifecycle_days_to_glacier" {
  type    = number
  default = 30
}
