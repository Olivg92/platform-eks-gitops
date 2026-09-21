# Platform components

One directory per component, each holding an Argo CD `Application` and its Helm values.
Install order comes from sync waves, not from the order of `kustomization.yaml`:

| Wave | Contents |
|---|---|
| -1 | Operators and their CRDs (Envoy Gateway, later cert-manager and External Secrets) |
| 0 | Resources that need those CRDs (the `Gateway`, monitoring) |
| 1 | Applications |

| Component | Role |
|---|---|
| [`envoy-gateway/`](envoy-gateway/) | Gateway API implementation, see [ADR 0003](../../docs/adr/0003-gateway-api-with-envoy-gateway.md) |
| [`gateway/`](gateway/) | The shared `GatewayClass` and `Gateway` that applications attach routes to |
