# 0012. CI reaches AWS through OIDC, with a read-only role

- **Status**: Accepted
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
the plan works while the environment is down and fails as soon as it is up. It also runs with `-lock=false`, since the role
cannot write the lock file and a plan changes nothing a lock would protect.

The provider and the role live in the bootstrap stack, next to the state bucket, because the demo
environment is destroyed every session and CI must keep working when it is.

## Consequences

- No AWS credential is stored anywhere in GitHub. There is nothing to rotate or revoke.
- The plan does not detect drift, only what a change would do. On an environment rebuilt from code
  every session there is little drift to detect, and a scheduled job with a broader role would be
  the answer if there were.
- **The state file contains secrets**, the Grafana password among them, so a role that reads it
  can read those too. That is why the trust policy is this narrow, and why the plan output relies
  on Terraform masking sensitive values before it is posted.
- The account id appears in role ARNs and in plan output. The role ARN is stored as a secret so
  GitHub masks it in public logs, and the account id is redacted from the comment before it is
  posted.
- The plan job skips pull requests from forks, which receive neither secrets nor an identity
  token, and runs started by Dependabot, which have no access to Actions secrets and so no role to
  assume. Their Terraform changes are still linted, validated and scanned by the `ci` workflow.
