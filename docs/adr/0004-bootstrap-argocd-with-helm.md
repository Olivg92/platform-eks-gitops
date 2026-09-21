# 0004. Install Argo CD with Helm, then let git take over

- **Status**: Accepted
- **Date**: 2026-09-22

## Context

Argo CD reconciles the cluster from git, but something has to install Argo CD itself.
This is the bootstrap problem: the tool that deploys everything cannot deploy itself from nothing.

## Options considered

1. **Argo CD manages itself from git**: elegant, and common in mature setups. But the first install
   still happens out of band, and a broken change to the Argo CD application can leave the cluster
   with no way to reconcile itself, which is a poor trade for a demo platform.
2. **Terraform installs Argo CD with the Helm provider**: keeps everything in one tool, but couples
   the cluster's contents to the infrastructure state, and makes `terraform destroy` responsible
   for Kubernetes objects.
3. **`helm upgrade --install` from the Makefile, pinned to a chart version**: two commands to read,
   no hidden state, and the same procedure on k3d and on EKS.

## Decision

Bootstrap Argo CD with Helm from the Makefile, with the chart version pinned in one place, then
apply a single root Application. From that point on, git drives every other component.

Values live in `local/argocd-values.yaml` for the local cluster; the AWS environment gets its own
file in step 1.4.

## Consequences

- The bootstrap is explicit and readable: two commands, no magic.
- Upgrading Argo CD means bumping one variable in the Makefile and re-running `make local-argocd`.
- Argo CD does not manage itself, so its own configuration drifts from git if changed by hand.
  Self-management would be the next step in a production setup.
