# SSM Module Variables

variable "environment" {
  description = "Deployment environment (dev | prod) — used in the parameter path prefix /parseon/<env>/<key>"
  type        = string
}

variable "parameters" {
  description = "Map of parameter name (path suffix) → plain-text value. Do NOT pass secrets here — use Secrets Manager instead."
  type        = map(string)
}
