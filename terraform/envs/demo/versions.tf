terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
  }

  backend "s3" {
    # Bucket and key come from backend.hcl, which is not committed because the
    # bucket name is account specific. See backend.hcl.example.
    # use_lockfile replaces the DynamoDB table older setups need.
  }
}
