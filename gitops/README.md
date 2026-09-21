# GitOps

Everything deployed to the cluster is declared here and reconciled by Argo CD.

| Directory | Purpose |
|---|---|
| [`bootstrap/`](bootstrap/) | Root app-of-apps, one per environment, the only thing applied by hand |
| [`envs/`](envs/) | What differs between environments: the component list and its patches |
| [`platform/`](platform/) | Platform components, one directory = one Argo CD Application |
| [`apps/`](apps/) | Workloads running on the platform (demo API) |
