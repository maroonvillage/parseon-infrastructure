variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "private_route_table_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "interface_services" {
  type    = list(string)
  default = []
}

variable "enable_s3_gateway_endpoint" {
  type    = bool
  default = false
}
