output "eso_role_arn" {
  description = "Role External Secrets Operator assumes."
  value       = aws_iam_role.eso.arn
}

output "secret_names" {
  description = "Secrets the operator is allowed to read."
  value = {
    grafana = aws_secretsmanager_secret.grafana.name
    demo    = aws_secretsmanager_secret.demo.name
  }
}
