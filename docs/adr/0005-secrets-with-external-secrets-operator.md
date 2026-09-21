# 0005. Keep secrets out of git with External Secrets Operator

- **Status**: Accepted
- **Date**: 2026-09-22

## Context

A GitOps repository is public, or at least readable by everyone who can clone it. Applications
still need credentials. The repository must therefore describe *which* secret an application needs,
without ever containing its value.

## Options considered

1. **Plain Kubernetes Secrets in git**: base64 is encoding, not encryption. Never an option here.
2. **Sealed Secrets**: encrypted values committed to git, decrypted in-cluster by a controller.
   Simple, but the secrets still live in git, rotation means a new commit, and the controller's
   private key becomes a single point of failure to back up.
3. **SOPS with age or KMS**: same idea with more flexibility, and the same drawback: the encrypted
   material is versioned forever, so a leaked key exposes the whole history.
4. **External Secrets Operator**: the repository holds only a reference — "read key X from store Y".
   Values live in a dedicated secret store and are rotated there, with no commit involved.

## Decision

Use External Secrets Operator. The store differs per environment and nothing else changes:

| Environment | Store | Authentication |
|---|---|---|
| Local (k3d) | Vault in dev mode, in-memory | Kubernetes auth: Vault trusts the operator's ServiceAccount |
| AWS (EKS) | AWS Secrets Manager | EKS Pod Identity |

Both are the same pattern: a workload identity, verified by the platform, instead of a shared
credential. No static token is stored anywhere, which is why the local setup uses Kubernetes auth
rather than Vault's dev root token.

Vault is configured at pod startup through the chart's `postStart` hook: dev mode keeps everything
in memory, so the auth method, the policy and the demo secret are replayed on every restart.

## Consequences

- The repository can stay public: it names secrets, it never carries them.
- Rotating a secret is an operation on the store, not a commit and a deploy.
- One more operator to run, and an outage of the store means new secrets cannot be materialised
  (existing ones keep working, since they are already Kubernetes Secrets).
- The local Vault is a demo: in memory, single replica, unsealed automatically, wiped on restart.
  Nothing about it is a production pattern, and that is deliberate — the production story is
  Secrets Manager plus Pod Identity.
