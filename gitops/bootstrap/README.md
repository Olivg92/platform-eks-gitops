# Argo CD bootstrap

The root `Application` (app-of-apps), one per environment. This is the only manifest applied by
hand, by `make local-up`. It points at `gitops/envs/<env>`, and Argo CD takes over from there.

See [ADR 0002](../../docs/adr/0002-app-of-apps-for-platform-components.md).
