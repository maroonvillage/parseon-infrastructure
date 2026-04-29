variable "region" {}
variable "project" {}
variable "api_image" {}
variable "worker_image" {}

variable "azs" {
  type = list(string)
}
