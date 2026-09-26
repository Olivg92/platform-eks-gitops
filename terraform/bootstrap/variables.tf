variable "region" {
  description = "AWS region. Accounts created with the new AWS sign-up have a single assigned region."
  type        = string
  default     = "eu-north-1"
}

variable "account_id" {
  description = "AWS account this stack is allowed to touch. Set it in terraform.tfvars, which is not committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be the 12 digit AWS account number."
  }
}

variable "state_bucket_name" {
  description = "Globally unique name for the state bucket. Set it in terraform.tfvars."
  type        = string
}

variable "github_repository" {
  description = "owner/name of the repository allowed to assume the CI role."
  type        = string
  default     = "Olivg92/platform-eks-gitops"
}
