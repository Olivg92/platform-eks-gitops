# 0007. kube-prometheus-stack as the baseline, Sloth to generate SLO rules

- **Status**: Accepted
- **Date**: 2026-09-22

## Context

The platform needs metrics, alerts and dashboards, and the project's point is not "Prometheus is
installed" but "this service has an SLO, an error budget, and alerts that page a human only when
the budget is burning fast enough to matter".

Writing multi-window multi-burn-rate alerts by hand means four recording rules and two alerting
rules per objective, each with windows and thresholds that are easy to get subtly wrong.

## Options considered

**For the metrics stack**

1. **Install Prometheus, Alertmanager, Grafana and the exporters separately**: full control, four
   charts to keep in sync, and the wiring between them becomes our problem.
2. **kube-prometheus-stack**: the Prometheus Operator, Alertmanager, Grafana, node-exporter and
   kube-state-metrics in one chart, with dashboards and default alerts included. The de-facto
   baseline, and what most teams actually run.
3. **A managed backend** (Amazon Managed Prometheus, Grafana Cloud): less to operate, but it hides
   exactly the part this project is meant to demonstrate, and it costs money.

**For SLO rules**

1. **Hand-written PrometheusRules**: no dependency, but repetitive and error-prone.
2. **Pyrra**: SLO objects plus its own UI. The UI is nice, but it is one more component to run and
   its rules are consumed through Pyrra rather than plain Prometheus.
3. **Sloth**: a small operator that turns a short `PrometheusServiceLevel` object into standard
   recording and alerting rules, following the Google SRE workbook. The output is plain
   PrometheusRules, readable in Prometheus and usable by any dashboard.

## Decision

Use kube-prometheus-stack for the metrics baseline and Sloth to generate SLO rules.

Prometheus is configured to watch every `ServiceMonitor`, `PodMonitor` and `PrometheusRule` in
the cluster rather than only those labelled by its own release, so applications and Sloth can ship
their own objects without knowing anything about the monitoring release.

The components a managed control plane does not expose (controller-manager, scheduler, etcd,
kube-proxy) are disabled. That is true of k3s locally and of EKS on AWS, and scraping them would
only produce alerts that fire forever.

Grafana's admin password is generated in the secret store and delivered by External Secrets
Operator ([ADR 0005](0005-secrets-with-external-secrets-operator.md)): the repository contains the
reference, never the credential.

## Consequences

- One chart covers metrics, alerting and dashboards, with sane defaults to build on.
- Defining an SLO becomes a ten-line object instead of six hand-written rules.
- The stack is sized for a demo: no persistence, 24h retention, one replica. Restarting the
  cluster loses the history, which is the intended trade-off for a laptop.
- In production this would gain persistent volumes, longer retention or remote write to a durable
  backend, and Alertmanager would route to a real paging provider rather than sit idle.
