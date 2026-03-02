variable "aws_region" {
  description = "AWS region to create IAM resources in"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI named profile to use for the bootstrap run"
  type        = string
  default     = "default"
}

variable "iam_group_name" {
  description = "Name of the IAM group for Terraform operators"
  type        = string
  default     = "terraform-operators"
}

variable "create_terraform_user" {
  description = "Set to true to create a brand-new IAM user. Set to false to add an existing user to the group."
  type        = bool
  default     = false
}

variable "terraform_user_name" {
  description = "Name of the new IAM user to create (only when create_terraform_user = true)"
  type        = string
  default     = "terraform-operator"
}

variable "existing_user_name" {
  description = "Name of the EXISTING IAM user to add to the terraform-operators group (only when create_terraform_user = false)"
  type        = string
  default     = ""
}
