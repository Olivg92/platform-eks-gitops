# 0012. CI reaches AWS through OIDC or not at all

- **Status**: Accepted. Off on the demo account, see below.
- **Date**: 2026-09-26

## Context

Pull requests that change the infrastructure should show what they would change before anyone
merges them. That needs `terraform plan`, and `terraform plan` needs AWS credentials in CI.

## Options considered

1. **An access key stored as a GitHub secret**: works, and is the thing this repository exists to
   avoid. A long-lived key in a CI system is one leaked log, one compromised action, or one
   forgotten rotation away from being someone else's key.
2. **OIDC with a broad role**, say `ReadOnlyAccess`: no stored key, but the role can read almost
   everything in the account, including every S3 object.
3. **OIDC with a role that reads the state and nothing else**, and a plan that does not refresh.

## Decision

GitHub Actions authenticates with OIDC: GitHub signs a token describing the run, AWS checks it
against the role's trust policy, and returns a one-hour session. The trust policy accepts exactly
one subject, `repo:Olivg92/platform-eks-gitops:pull_request`: not another repository of the same
owner, not a push, not a branch. Fork pull requests never receive a token.

The role can list the state bucket, read its objects, and list EKS addon versions. Nothing else.
The plan runs with `-refresh=false`, which compares the configuration with the last applied state
instead of querying every managed resource. That answers the question a pull request asks, what
does this change, without any permission on EC2, IAM or Secrets Manager.

Data sources are still read during a plan, refresh or not, and the eks module has one: the addon
version catalog, a public list with no account data behind it. The permissions above are the
complete set, taken from a debug log of a real plan rather than guessed: without the EKS lookup
the plan works while the environment is down and fails as soon as it is up. It also runs with
`-lock=false`, since the role cannot write the lock file and a plan changes nothing a lock would
protect.

The provider and the role live in the bootstrap stack, next to the state bucket, because the demo
environment is destroyed every session and CI must keep working when it is.

## This account cannot trust GitHub

The first apply of the provider was refused: `iam:CreateOpenIDConnectProvider`, explicit deny in a
service control policy. The account was created through the new AWS sign-up experience, whose
AWS-managed SCP denies `iam:*Provider*` on the Free and the Paid plan alike
([Service control policies for projects](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html)).
The only way to lift it is to activate advanced features, which cannot be undone and removes the
spend limit that caps what this demo can cost.

A plan comment is worth neither. So:

- the provider and the role stay in the code, behind `enable_github_oidc`, off by default. On a
  standard account, that one variable turns them on;
- the workflow runs only once the repository variable `TF_STATE_BUCKET` is set, and is skipped
  otherwise, so nothing fails;
- there is no fallback to an access key. CI reaches AWS through OIDC or not at all.

The loss is smaller than it sounds. The plan compares the code with the last applied state, and
this environment is destroyed at the end of every session: most of the time the state is empty,
and the comment would announce the whole environment as new, whatever the pull request changes.
Every Terraform change is still formatted, validated, linted and scanned by the `ci` workflow, and
a plan can still be run locally at any time.

The same SCP would have blocked IRSA, which needs an IAM OIDC provider for the cluster. EKS Pod
Identity, chosen in [ADR 0010](0010-pod-identity-for-workload-credentials.md), turns out to be the
only one of the two that works on this account.

## Consequences

- No AWS credential is stored anywhere in GitHub. There is nothing to rotate or revoke.
- The plan does not detect drift, only what a change would do. On an environment rebuilt from code
  every session there is little drift to detect, and a scheduled job with a broader role would be
  the answer if there were.
- **A role that reads the state reads everything in it**, so the state holds no secret: the Grafana
  password is an ephemeral value, sent to Secrets Manager through a write-only argument and never
  stored. The trust policy stays narrow all the same, since the state still maps the whole
  environment.
- Where the plan is on, the account id appears in role ARNs and in plan output. The role ARN is
  stored as a secret so GitHub masks it in public logs, and the account id is redacted from the
  comment before it is posted.
- The plan job skips pull requests from forks, which receive neither secrets nor an identity
  token, and runs started by Dependabot, which have no access to Actions secrets and so no role to
  assume. Their Terraform changes are still linted, validated and scanned by the `ci` workflow.
