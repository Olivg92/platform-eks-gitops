# Local environment

| File | Purpose |
|---|---|
| `k3d-cluster.yaml` | Cluster definition: two nodes, Kubernetes pinned to the EKS default version, Traefik disabled, ports 8080/8443 mapped to the gateway |
| `argocd-values.yaml` | Argo CD Helm values for a laptop: one replica of each component, no Dex, no notifications |

Both are consumed by `make local-up`.
