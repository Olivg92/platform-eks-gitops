output "state_bucket" {
  description = "Name of the state bucket, to be used in the backend configuration of the other stacks."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "Region the bucket lives in."
  value       = var.region
}
