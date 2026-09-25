terraform {
  # 1.10 introduced native S3 state locking, which removes the DynamoDB table
  # every older tutorial asks for.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
  }

  # Applied once with local state: this stack is what creates the remote backend
  # every other stack will use. Its own state stays on the operator's machine and
  # is never committed (see .gitignore).
}
