variable "name" {
  description = "Prefix for the resources this module creates."
  type        = string
}

variable "cluster_name" {
  description = "Cluster the Pod Identity association belongs to."
  type        = string
}

variable "secret_prefix" {
  description = <<-EOT
    Optional prefix for the secret names. Empty by default so a secret is called
    "grafana" here and "secret/grafana" in the local Vault, which lets the very
    same ExternalSecret manifest work in both environments.
  EOT
  type        = string
  default     = ""
}
