# Architecture Decision Records

Short documents capturing a significant technical choice, its context and its trade-offs.
New ADRs start from [the template](0000-template.md) and are never rewritten once accepted: a later ADR supersedes them instead.

| # | Decision | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-app-of-apps-for-platform-components.md) | Use the app-of-apps pattern for platform components | Accepted |
| [0003](0003-gateway-api-with-envoy-gateway.md) | Route ingress traffic with Gateway API, implemented by Envoy Gateway | Accepted |
| [0004](0004-bootstrap-argocd-with-helm.md) | Install Argo CD with Helm, then let git take over | Accepted |
| [0005](0005-secrets-with-external-secrets-operator.md) | Keep secrets out of git with External Secrets Operator | Accepted |
| [0006](0006-shared-base-with-environment-overlays.md) | Share one base between environments, overlay what differs | Accepted |
| [0007](0007-monitoring-baseline-and-slo-generation.md) | kube-prometheus-stack as the baseline, Sloth to generate SLO rules | Accepted |
| [0008](0008-slo-definitions-for-the-demo-api.md) | What the demo API promises, and how it is measured | Accepted |
