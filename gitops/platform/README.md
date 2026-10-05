# Platform components

One directory per component shared by every environment, each holding an Argo CD `Application`
and its Helm values or manifests. Install order comes from sync waves, not from
`kustomization.yaml`:

| Wave | Contents |
|---|---|
| -2 | Operators and their CRDs: Envoy Gateway, cert-manager, External Secrets Operator |
| -1 | What those operators need first: the certificate issuer, the secret store and its secrets |
| 0 | What consumes them: the `Gateway`, kube-prometheus-stack, Sloth |
| 1 | Routes and workloads: the Grafana route, the demo API |

The secret store, the `Gateway`, the demo API and, locally, Vault are environment applications, in
[`gitops/envs/<env>`](../envs/), ordered by the same waves.

| Component | Role |
|---|---|
| [`envoy-gateway/`](envoy-gateway/) | Gateway API implementation ([ADR 0003](../../docs/adr/0003-gateway-api-with-envoy-gateway.md)) |
| [`cert-manager/`](cert-manager/) | Certificates, wired to Gateway API |
| [`issuer/`](issuer/) | The certificate authority cert-manager signs the listener certificates with |
| [`external-secrets/`](external-secrets/) | Secrets from an external store ([ADR 0005](../../docs/adr/0005-secrets-with-external-secrets-operator.md)) |
| [`secrets/`](secrets/) | The secrets every environment needs, such as Grafana's admin credentials |
| [`gateway/base/`](gateway/base/) | The shared `GatewayClass` and `Gateway`; each environment overlays its TLS and hostname |
| [`kube-prometheus-stack/`](kube-prometheus-stack/) | Prometheus, Alertmanager and Grafana ([ADR 0007](../../docs/adr/0007-monitoring-baseline-and-slo-generation.md)) |
| [`sloth/`](sloth/) | Turns SLO objects into multi-window burn-rate rules |
| [`monitoring-route/`](monitoring-route/) | The route to Grafana through the gateway, the same in both environments |
