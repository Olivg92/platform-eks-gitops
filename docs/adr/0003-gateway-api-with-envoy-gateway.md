# 0003. Route ingress traffic with Gateway API, implemented by Envoy Gateway

- **Status**: Accepted
- **Date**: 2026-09-22

## Context

The platform needs a single entry point for HTTP traffic, both on k3d and on EKS.
The traditional answer is the Ingress API, but it has been feature-frozen for years, and every
controller extends it with its own annotations, which do not transfer between clusters.

## Options considered

1. **ingress-nginx**: the best known controller, but the project has entered maintenance and will
   stop receiving updates. Building a new platform on it today means planning a migration immediately.
2. **Traefik with the Ingress API**: bundled with k3s, so nothing to install locally, but it would
   still have to be installed on EKS, and routing would rely on provider-specific annotations.
3. **Gateway API with Traefik**: the right API, but Traefik's implementation covers less of the
   specification than dedicated implementations.
4. **Gateway API with Envoy Gateway**: Gateway API is the successor to Ingress, with role-oriented
   resources (GatewayClass, Gateway, HTTPRoute) and a portable specification. Envoy Gateway is the
   reference implementation maintained by the Envoy project, and Envoy is also what AWS runs inside
   App Mesh and what most service meshes use as a data plane.

## Decision

Use Gateway API, implemented by Envoy Gateway. k3s ships with Traefik, so it is disabled in the k3d
cluster configuration to leave port 80 to Envoy.

The platform exposes one `Gateway` named `platform`; applications attach to it with `HTTPRoute`
objects from their own namespace. This mirrors how a platform team and application teams share
responsibility: the platform owns the listener and the certificates, applications own their routes.

## Consequences

- The same routing manifests work on k3d and on EKS, with no annotation rewriting.
- One more component to install locally, where Traefik came for free.
- Gateway API is newer than Ingress, so fewer answers exist online and some tools still lack
  schema support (`kubeconform` runs with `-ignore-missing-schemas` for CRDs).
- TLS is not configured yet: it arrives with cert-manager in the next step.
