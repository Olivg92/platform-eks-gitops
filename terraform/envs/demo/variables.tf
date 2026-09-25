variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-north-1"
}

variable "account_id" {
  description = "AWS account this environment is allowed to touch."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be the 12 digit AWS account number."
  }
}

variable "name" {
  description = "Name of the environment, used as a prefix for every resource."
  type        = string
  default     = "platform-demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version, kept in step with the local k3d cluster."
  type        = string
  default     = "1.36"
}

variable "node_count" {
  description = "Number of Spot nodes."
  type        = number
  default     = 2
}

variable "availability_zones" {
  description = "Zones the public subnets are created in."
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b"]
}

variable "api_public_access_cidrs" {
  description = <<-EOT
    Who may reach the Kubernetes API. No default on purpose: `make up` fills it with the
    current public address of the machine running it, so the endpoint is never left open
    to the internet by forgetting a flag.
  EOT
  type        = list(string)

  validation {
    condition     = !contains(var.api_public_access_cidrs, "0.0.0.0/0")
    error_message = "Refusing to expose the Kubernetes API to the whole internet."
  }
}
