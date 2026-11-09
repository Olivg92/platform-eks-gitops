# Continuous integration

Every pull request runs the same checks as a developer machine, from the same
[`.pre-commit-config.yaml`](../.pre-commit-config.yaml): a check that only exists in CI is a check
nobody can reproduce before pushing.

| Job | What it catches |
|---|---|
| lint and security | Terraform format, validation, tflint and checkov; kubeconform and yamllint on manifests; gitleaks on every commit of the pull request; actionlint for the workflows themselves |
| demo-api tests | The pytest suite, including the test that pins the metric labels the SLOs depend on |
| manifests render | Every kustomization under `gitops/` rendered and validated, 14 today. The environment roots only list Argo CD Applications; the patches that can break live one level down, so each one is rendered |
| demo-api image | Built and scanned with Trivy when the application changes. Findings go to the Security tab; a fixable critical one fails the build. Published to GHCR on `main` only, tagged with the commit sha |
| image freshness | Every Monday, and on demand from the Actions tab. Fails when a pinned base image is more than 14 days old, which means Dependabot missed its bump, and rescans the image published for `main` against the day's vulnerabilities ([ADR 0011](adr/0011-runtime-image-with-no-known-vulnerabilities.md)) |
| terraform plan | Off on the demo account, see below. Where it is on: the plan of `envs/demo` on pull requests touching the infrastructure, posted as a comment |

[`scripts/render-manifests.sh`](../scripts/render-manifests.sh) is the same render check,
runnable locally.

The gitleaks hook reads what is staged, which is right before a commit and nothing on a CI
checkout. So the job also runs gitleaks on the commits themselves, those of the pull request or
of the push to `main`: a secret added then deleted still fails it. The same scan of a branch,
locally: `gitleaks git --redact --log-opts="origin/main..HEAD"`.
[ADR 0013](adr/0013-scan-commits-for-secrets-with-the-gitleaks-binary.md) explains why it runs
the gitleaks binary rather than its GitHub Action.

## AWS access, through OIDC only

The plan authenticates to AWS with OIDC only: no access key exists anywhere in GitHub. The role
it assumes can read the Terraform state and list EKS addon versions, nothing else, and only pull
requests of this repository can assume it. It is **off on the account this demo runs on**, whose
AWS-managed policies forbid OIDC providers; [ADR 0012](adr/0012-ci-reaches-aws-through-oidc.md)
explains why no access key takes its place. On a standard account, apply `terraform/bootstrap` with
`enable_github_oidc = true`, then add, under Settings, Secrets and variables, Actions:

| Name | Kind | Value |
|---|---|---|
| `AWS_PLAN_ROLE_ARN` | secret | output `ci_plan_role_arn` of `terraform/bootstrap` |
| `AWS_ACCOUNT_ID` | secret | the account id, masked in logs and redacted from comments |
| `TF_STATE_BUCKET` | variable | the state bucket name |

## Pinning, and what keeps the pins fresh

Actions are pinned to a commit rather than a tag, since a tag can be moved to point at different
code. Base images are pinned by digest, and Python dependencies to exact versions. Dependabot
raises the pull requests that bump all of them every week, so pinning does not mean going stale,
and the image freshness workflow fails if Dependabot ever stops.
