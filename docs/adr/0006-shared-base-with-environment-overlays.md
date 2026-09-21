# 0006. Share one base between environments, overlay what differs

- **Status**: Accepted
- **Date**: 2026-09-22

## Context

The same platform has to run on k3d and on EKS. Some things are identical (the operators, the
gateway topology), some cannot be (the certificate issuer, the secret store, the load balancer).
Duplicating the manifests per environment guarantees they drift apart.

## Options considered

1. **One directory per environment, fully duplicated**: obvious to read, impossible to keep in sync.
2. **Helm chart of charts with per-environment values**: powerful, but it turns plain manifests into
   templates and hides what is actually applied.
3. **Kustomize base plus overlays**: shared manifests in `gitops/platform`, differences expressed
   as patches in `gitops/envs/<env>`, and the rendered result stays readable.

## Decision

Use a shared base with per-environment overlays:

- `gitops/platform/` holds what every environment runs, including the gateway base.
- `gitops/envs/<env>/` holds the environment's application list, its patches (TLS issuer,
  hostname) and the components that exist only there, such as the dev Vault.
- The root Application of an environment points at `gitops/envs/<env>`, so a new environment is a
  new directory and a new root Application, not a fork of the manifests.

## Consequences

- Adding a component to every environment is a one-file change in `gitops/platform`.
- What differs between local and AWS is visible in one place, which is also what the reader wants
  to understand first.
- Reading a manifest no longer tells the whole story: the patches have to be read too, or rendered
  with `kubectl kustomize gitops/envs/local`.
