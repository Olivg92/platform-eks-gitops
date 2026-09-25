# 0010. Give workloads AWS credentials with EKS Pod Identity

- **Status**: Accepted
- **Date**: 2026-09-25

## Context

External Secrets Operator has to read AWS Secrets Manager. The question is how a pod proves who it
is to AWS, and the answer decides whether this platform has a credential to protect or not.

## Options considered

1. **An IAM user with access keys, stored as a Kubernetes Secret**: works everywhere, and creates
   exactly what the whole secrets design exists to avoid: a long-lived credential sitting in the
   cluster, waiting to leak or to be forgotten during a rotation.
2. **Permissions on the node role**: no credential to store, but every pod on the node inherits
   them. A compromised sidecar in an unrelated namespace could read the platform's secrets.
3. **IRSA (IAM Roles for Service Accounts)**: the established answer. Per-ServiceAccount, short
   lived, but it needs an OIDC provider per cluster, a trust policy with the issuer URL inside it,
   and a service account annotation. Destroying and recreating a cluster means a new issuer, so the
   role's trust policy has to be rewritten every time.
4. **EKS Pod Identity**: same guarantee, expressed as an association between a cluster, a namespace,
   a ServiceAccount and a role. No OIDC provider, no issuer URL in the trust policy, and the role is
   reusable across cluster rebuilds.

## Decision

Use EKS Pod Identity. The association is a Terraform resource; the role's policy allows
`GetSecretValue` and `DescribeSecret` on the two named secrets, nothing else.

This mirrors what the local environment does with Vault: there, Vault trusts the same
ServiceAccount through Kubernetes authentication. Both environments grant a workload identity that
the platform verifies, rather than a secret that has to be stored and rotated.

## Consequences

- Nothing in the cluster or the repository holds an AWS credential. `make down` leaves nothing to
  revoke.
- The blast radius of the operator is two secrets, readable, in one region.
- Pod Identity is EKS specific. A platform that also runs on another provider would use IRSA, or
  the provider's own equivalent, and the `ClusterSecretStore` manifest would stay the same.
- The environment this platform runs on is invisible to the application manifests: the store is
  called `platform` in both, and the demo API's `ExternalSecret` does not know whether the value
  comes from Vault or from Secrets Manager.
