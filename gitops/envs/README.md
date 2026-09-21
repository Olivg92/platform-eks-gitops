# Environments

What differs between environments, on top of the shared [`platform/`](../platform/) base:
the list of applications, the certificate issuer, the secret store, and components that exist
in one environment only.

| Directory | Cluster | Notable differences |
|---|---|---|
| [`local/`](local/) | k3d | Vault in dev mode, self-signed certificate authority |
| `aws/` | EKS | Planned in step 1.4: AWS Secrets Manager, Let's Encrypt, cloud load balancer |

See [ADR 0006](../../docs/adr/0006-shared-base-with-environment-overlays.md).
