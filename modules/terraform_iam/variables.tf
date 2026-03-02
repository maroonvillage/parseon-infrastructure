# terraform_iam Module Variables

variable "group_name" {
  description = "Name of the IAM group to create for Terraform operators"
  type        = string
  default     = "terraform-operators"
}

variable "create_user" {
  description = "Set to true to create a new IAM user and add it to the group. Set to false to add an existing user instead."
  type        = bool
  default     = false
}

variable "user_name" {
  description = "Name of the new IAM user to create (only used when create_user = true)"
  type        = string
  default     = "terraform-operator"
}

variable "existing_user_name" {
  description = "Name of an existing IAM user to add to the group (only used when create_user = false)"
  type        = string
  default     = ""
}
