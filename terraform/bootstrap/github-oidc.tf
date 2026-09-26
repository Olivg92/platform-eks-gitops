# Lets GitHub Actions obtain short-lived AWS credentials without any stored key.
#
# GitHub signs a token for each workflow run describing where it comes from:
# repository, event, branch. AWS checks the signature against GitHub's identity
# provider and hands out a one-hour session, but only if the claims match the
# trust policy below. Nothing is stored in GitHub that could leak or need rotating.
#
# Kept in the bootstrap stack rather than the demo environment: the demo is
# destroyed every session, and CI must keep working when it is.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "ci_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pull requests of this repository, and nothing else: not another
    # repository of the same owner, not a push, not a fork. Fork pull requests
    # never receive an identity token from GitHub in the first place.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

resource "aws_iam_role" "ci_plan" {
  name                 = "platform-eks-gitops-ci-plan"
  description          = "Assumed by GitHub Actions on pull requests to run terraform plan"
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_trust.json
  max_session_duration = 3600
}

# Read the state, plus the one lookup the configuration makes, and nothing else.
#
# The plan runs with -refresh=false, so it compares the configuration with the
# last applied state instead of querying every managed resource: that answers
# what a pull request changes, which is the question. Data sources are still
# read during a plan, refresh or not, and the eks module has one: the addon
# version catalog. The calls below are the complete list, taken from a debug log
# of a real plan, not guessed.
data "aws_iam_policy_document" "ci_plan" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  # Covers GetObject and HeadObject, both of which the S3 backend sends.
  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  # aws_eks_addon_version, read at plan time once the cluster exists. A public
  # catalog of addon versions: no account data behind it. The action does not
  # support resource-level permissions, hence "*".
  statement {
    sid       = "ReadAddonCatalog"
    actions   = ["eks:DescribeAddonVersions"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_plan" {
  name   = "read-terraform-state"
  role   = aws_iam_role.ci_plan.id
  policy = data.aws_iam_policy_document.ci_plan.json
}
