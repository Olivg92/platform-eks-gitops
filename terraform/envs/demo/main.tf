# The demo environment: one VPC, one cluster, two Spot nodes.
#
# Expected cost while it runs, in eu-north-1:
#   EKS control plane        $0.10/hour
#   2 Spot t3.medium         ~$0.03/hour
#   2 public IPv4 addresses  $0.01/hour
#   40 GB gp3                ~$0.005/hour
#   -------------------------------------
#   about $0.15/hour, plus ~$0.025/hour once a load balancer exists.
#
# `make down` removes all of it. The state bucket is the only thing that stays.

module "vpc" {
  source = "../../modules/vpc"

  name = var.name
  # Named explicitly rather than discovered: a data source would silently return
  # a third zone the day AWS adds one, changing the plan without anyone asking.
  # Two zones is enough for the load balancer, without paying for a third set of
  # addresses on a cluster that lives for an afternoon.
  availability_zones = var.availability_zones
}

module "eks" {
  source = "../../modules/eks"

  name                = var.name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = module.vpc.public_subnet_ids
  desired_size        = var.node_count
  public_access_cidrs = var.api_public_access_cidrs
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  name         = var.name
  cluster_name = module.eks.cluster_name
}
