resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    # API instead of the aws-auth ConfigMap: access is granted with Terraform
    # like any other resource, and a broken entry no longer locks everyone out.
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Defining the launch template ourselves is what makes IMDSv2 and the disk type
# explicit rather than inherited from an AWS default that may change.
resource "aws_launch_template" "node" {
  name_prefix = "${var.name}-node-"

  metadata_options {
    http_tokens = "required"
    # A hop limit of 1 keeps the instance credentials reachable from the host but
    # not from inside a pod, which is the usual path of a container escape.
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = false # detailed monitoring is billed per instance and adds nothing here
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.name}-node"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-spot"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  # Spot is about 70% cheaper than on demand. An interruption reschedules the
  # pods, which is exactly the behaviour a demo platform should survive.
  capacity_type  = "SPOT"
  instance_types = var.instance_types
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.desired_size
    max_size     = var.desired_size
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# Addons, pinned to the versions AWS considers default for this Kubernetes
# release so an upgrade is a visible change rather than a surprise.
data "aws_eks_addon_version" "this" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent"])

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.this["vpc-cni"].version

  # Without this the NetworkPolicy objects the applications ship are accepted by
  # the API server and silently ignored by the data plane.
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "others" {
  for_each = toset(["coredns", "kube-proxy", "eks-pod-identity-agent"])

  cluster_name  = aws_eks_cluster.this.name
  addon_name    = each.key
  addon_version = data.aws_eks_addon_version.this[each.key].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
