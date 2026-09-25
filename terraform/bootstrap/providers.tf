provider "aws" {
  region = var.region

  # Refuses to run against any other account, which matters on a machine that
  # also has work credentials configured.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "platform-eks-gitops"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
