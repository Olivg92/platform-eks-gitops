# 0002. Use the app-of-apps pattern for platform components

- **Status**: Accepted
- **Date**: 2026-09-22

## Context

The cluster needs a dozen platform components (ingress, certificates, secrets, monitoring).
Installing them by hand, or with a script full of `helm install` calls, means the cluster state
depends on who ran what and when. We want the repository to be the source of truth, and a single
command to go from an empty cluster to a working platform.

## Options considered

1. **A script calling Helm**: simple to read, but no drift detection, no rollback, and the cluster
   slowly diverges from the repository.
2. **One Argo CD Application per component, applied by hand**: declarative, but the list of
   components lives outside git, so adding one is still a manual step.
3. **App-of-apps**: a single root Application points at a directory of Application manifests.
   Adding a component means adding a file and opening a pull request.
4. **ApplicationSet with a git generator**: same result with less boilerplate, but the generated
   applications are harder to read for someone discovering the repository.

## Decision

Use the app-of-apps pattern. `make local-up` applies exactly one manifest, the root Application,
which points at `gitops/envs/<env>`. Everything else is reconciled from git.
Install order is expressed with Argo CD sync waves: operators and CRDs in wave -1, the resources
that depend on them in wave 0, applications in wave 1.

## Consequences

- One command bootstraps the platform, and the same manifests serve local and AWS.
- Drift is corrected automatically: components have `selfHeal` and `prune` enabled.
- Applications committed to git track `main`, so testing a branch needs the development helper
  `scripts/dev-follow-revision.sh`, which repoints them temporarily.
- In production this would be paired with a stricter Argo CD project than `default`, restricting
  which repositories, namespaces and cluster-scoped resources each application may touch.
