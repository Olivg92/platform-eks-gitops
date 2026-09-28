# Architecture

The [README](../README.md#architecture) has the overview. This page follows two things through the
platform: a request, and a secret. Both take the same path on k3d and on EKS; only the first hop
and the secret store change.

## A request

```mermaid
flowchart LR
    client([Client]) -->|"HTTPS, demo.platform.local"| edge

    subgraph edge[First hop]
        k3d["k3d: host port 8443,<br/>k3d load balancer"]
        nlb["EKS: Network Load Balancer,<br/>requested by the EnvoyProxy config"]
    end

    edge --> envoy["Envoy proxy pods<br/>namespace envoy-gateway-system"]
    envoy -->|"Gateway platform,<br/>listener *.platform.local:443"| route["HTTPRoute<br/>demo.platform.local"]
    route -->|"NetworkPolicy: only the<br/>gateway namespace may enter"| api["demo-api pods<br/>namespace demo, port 8000"]

    ca["cert-manager<br/>ClusterIssuer platform-ca"] -.->|"certificate platform-tls"| envoy
    prom["Prometheus<br/>namespace monitoring"] -.->|"scrapes /metrics,<br/>also allowed by the policy"| api
```

- **One gateway, owned by the platform.** Applications attach `HTTPRoute` objects from their own
  namespace; they never open a port of their own ([ADR 0003](adr/0003-gateway-api-with-envoy-gateway.md)).
- **TLS ends at the gateway**, with a wildcard certificate issued by the cluster's own authority.
  A public name and a public issuer would replace it in production; nothing else would change.
- **The application namespace denies all ingress by default.** Traffic from the gateway,
  Prometheus and the probe is allowed by name, and anything else, a pod in another namespace
  included, is refused.

## A secret

```mermaid
flowchart LR
    subgraph store[Secret store]
        vault["k3d: Vault in dev mode"]
        sm["EKS: AWS Secrets Manager"]
    end

    eso["External Secrets Operator<br/>ClusterSecretStore platform"] -->|"proves who it is"| store
    vault -.->|"trusts its ServiceAccount<br/>(Kubernetes auth)"| eso
    sm -.->|"trusts its Pod Identity<br/>(EKS association)"| eso
    eso -->|"writes"| k8s["Kubernetes Secret<br/>grafana-admin"]
    k8s -->|"read at start"| grafana[Grafana]
    tf["Terraform, on AWS"] -->|"ephemeral password,<br/>write-only argument"| sm
```

- **Git holds the name of a secret, never its value.** The `ExternalSecret` says which key it
  needs; the operator fetches it and writes an ordinary Kubernetes Secret
  ([ADR 0005](adr/0005-secrets-with-external-secrets-operator.md)).
- **No token is stored to reach the store.** Locally, Vault trusts the operator's ServiceAccount;
  on EKS, the Pod Identity association hands its pod short-lived AWS credentials, for two named
  secrets only ([ADR 0010](adr/0010-pod-identity-for-workload-credentials.md)).
- **On AWS, the value is not in the Terraform state either.** The password is generated as an
  ephemeral value and sent to Secrets Manager through a write-only argument.
- **Consumers read a secret when they start.** A rotated value reaches Grafana on its next restart,
  which is what `make grafana-reload` does by hand and Reloader would do in production.
