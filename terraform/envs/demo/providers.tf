provider "aws" {
  region = var.region

  # A machine with several AWS profiles is one typo away from creating a demo
  # cluster in the wrong account. This makes that a hard error.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "platform-eks-gitops"
      ManagedBy = "terraform"
      Stack     = "demo"
      # Everything here is meant to be destroyed the same day.
      Lifecycle = "ephemeral"
    }
  }
}
