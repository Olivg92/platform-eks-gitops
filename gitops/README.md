# GitOps

Everything deployed to the cluster is declared here and reconciled by ArgoCD.

| Directory | Purpose |
|---|---|
| [`bootstrap/`](bootstrap/) | Root app-of-apps, the only thing applied by hand |
| [`platform/`](platform/) | Platform components, one directory = one ArgoCD Application |
| [`apps/`](apps/) | Workloads running on the platform (demo API) |
