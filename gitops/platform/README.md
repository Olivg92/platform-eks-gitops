# Platform components

One directory per component shared by every environment, each holding an Argo CD `Application`
and its Helm values. Install order comes from sync waves, not from `kustomization.yaml`:

| Wave | Contents |
|---|---|
| -1 | Operators and their CRDs: Envoy Gateway, cert-manager, External Secrets Operator |
| 0 | Resources those operators consume: the `Gateway`, the certificate issuer |
| 1 | Applications and their secrets |

| Component | Role |
|---|---|
| [`envoy-gateway/`](envoy-gateway/) | Gateway API implementation ([ADR 0003](../../docs/adr/0003-gateway-api-with-envoy-gateway.md)) |
| [`cert-manager/`](cert-manager/) | Certificates, wired to Gateway API |
| [`external-secrets/`](external-secrets/) | Secrets from an external store ([ADR 0005](../../docs/adr/0005-secrets-with-external-secrets-operator.md)) |
| [`gateway/base/`](gateway/base/) | The shared `GatewayClass` and `Gateway`; each environment overlays its TLS and hostname |
