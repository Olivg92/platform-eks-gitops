output "state_bucket" {
  description = "Name of the state bucket, to be used in the backend configuration of the other stacks."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "Region the bucket lives in."
  value       = var.region
}

output "ci_plan_role_arn" {
  description = "Role the terraform plan workflow assumes, null unless enable_github_oidc is set. Store it as the AWS_PLAN_ROLE_ARN secret."
  value       = one(aws_iam_role.ci_plan[*].arn)
}
