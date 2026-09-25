output "cluster_name" {
  description = "Cluster name, used by `aws eks update-kubeconfig`."
  value       = module.eks.cluster_name
}

output "region" {
  description = "Region the environment lives in."
  value       = var.region
}

output "kubeconfig_command" {
  description = "Command that points kubectl at this cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --profile perso"
}

output "secret_names" {
  description = "Secrets in Secrets Manager the platform reads."
  value       = module.workload_identity.secret_names
}
