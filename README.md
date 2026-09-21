# platform-eks-gitops

A production-style Kubernetes platform on AWS EKS, fully managed with GitOps:
infrastructure as code, secrets management, observability with SLOs, and CI with zero static credentials.

> **Status: work in progress.** The repository layout is in place; components are being added step by step.
> See the [roadmap](#roadmap).

## Why this project

Running a Kubernetes platform is more than installing a cluster. This repository shows the full lifecycle:

- **Build** it reproducibly: Terraform for AWS, ArgoCD for everything inside the cluster.
- **Operate** it: SLOs with multi-window burn-rate alerts, dashboards and runbooks.
- **Keep it cheap and safe**: one command to create, one to destroy, no NAT Gateway, Spot nodes, no secrets in Git.

Everything runs **locally on k3d first** (free), and on EKS only for validation and demos.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the target architecture diagram.

## Quickstart (local)

_Coming in step 1.2._ The goal is three commands:

```bash
git clone https://github.com/Olivg92/platform-eks-gitops.git && cd platform-eks-gitops
make check-tools
make local-up
```

Run `make help` to list all available targets.

## Repository layout

| Path | Content |
|---|---|
| [`terraform/`](terraform/) | AWS infrastructure: state bootstrap, modules (VPC, EKS, IAM), demo environment |
| [`gitops/`](gitops/) | Everything ArgoCD deploys: app-of-apps, platform components, applications |
| [`apps/demo-api/`](apps/demo-api/) | Demo API used to showcase SLOs |
| [`docs/`](docs/) | Architecture, [decision records](docs/adr/), runbooks |
| [`.github/workflows/`](.github/workflows/) | CI pipelines |

## Technical choices

Each non-trivial decision is documented as an [Architecture Decision Record](docs/adr/).

## Cost

The EKS environment is meant to live for a few hours, then be destroyed with `make down`.
The measured cost of a demo session will be documented here.

## What I would do differently in production

_To be written: multi-AZ, Karpenter, backups with Velero, policies with Kyverno, and more._

## Roadmap

- [x] Repository layout, linting and secret scanning (pre-commit)
- [ ] Local platform on k3d: ArgoCD, Gateway API, cert-manager, External Secrets, Prometheus stack
- [ ] Demo API with SLOs, burn-rate alerts, dashboard and runbooks
- [ ] AWS EKS with Terraform (no NAT, Spot nodes, Pod Identity)
- [ ] CI with GitHub Actions and OIDC authentication to AWS
- [ ] Documentation: ADRs, screenshots, production notes

## Development

```bash
make lint   # runs all pre-commit checks (formatting, YAML, Terraform, secrets)
```
