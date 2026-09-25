variable "name" {
  description = "Prefix for the resources this module creates."
  type        = string
}

variable "cluster_name" {
  description = "Cluster the Pod Identity association belongs to."
  type        = string
}

variable "secret_prefix" {
  description = "Prefix the platform secrets live under in Secrets Manager."
  type        = string
  default     = "platform"
}
