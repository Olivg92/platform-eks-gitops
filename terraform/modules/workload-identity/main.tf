# What External Secrets Operator reads on AWS, and the identity it reads it with.
#
# The local environment uses Vault in dev mode and Kubernetes auth; here the
# store is Secrets Manager and the identity is EKS Pod Identity. Same pattern in
# both: the workload proves who it is, nothing is stored as a shared credential.

resource "random_password" "grafana" {
  length  = 24
  special = false # avoids quoting surprises when the value travels through YAML
}

# The values live here, never in git. `make down` deletes them for real rather
# than scheduling them, so the next `make up` can recreate the same names.
resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${var.secret_prefix}/grafana"
  description             = "Grafana admin credentials, read by External Secrets Operator"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id = aws_secretsmanager_secret.grafana.id

  secret_string = jsonencode({
    admin-user     = "admin"
    admin-password = random_password.grafana.result
  })
}

resource "aws_secretsmanager_secret" "demo" {
  name                    = "${var.secret_prefix}/demo"
  description             = "Demo secret, the one make local-verify prints"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "demo" {
  secret_id     = aws_secretsmanager_secret.demo.id
  secret_string = jsonencode({ message = "stored in Secrets Manager, never in git" })
}

data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.name}-external-secrets"
  description        = "Assumed by the External Secrets Operator pod through EKS Pod Identity"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

# Read access, on these two secrets only. Not "secretsmanager:*", not "*".
data "aws_iam_policy_document" "eso" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      aws_secretsmanager_secret.grafana.arn,
      aws_secretsmanager_secret.demo.arn,
    ]
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = "read-platform-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso.json
}

# The association is what ties a Kubernetes ServiceAccount to the role. No key,
# no token to rotate: the Pod Identity agent hands short-lived credentials to
# that ServiceAccount and to no other.
resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso.arn
}
