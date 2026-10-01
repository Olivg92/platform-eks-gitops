output "cluster_name" {
  description = "Cluster name, used by `aws eks update-kubeconfig`."
  value       = module.eks.cluster_name
}

output "region" {
  description = "Region the environment lives in."
  value       = var.region
}

output "kubeconfig_command" {
  description = "Writes this cluster's credentials to its own kubeconfig file. `make up` runs it."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --kubeconfig ~/.kube/platform-eks-gitops-aws"
}

output "secret_names" {
  description = "Secrets in Secrets Manager the platform reads."
  value       = module.workload_identity.secret_names
}

output "api_public_access_cidrs" {
  description = "Addresses allowed to reach the Kubernetes API, as applied. Read back by the CI plan."
  value       = var.api_public_access_cidrs
}
