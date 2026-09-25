# demo-api is burning its latency error budget

**Alert**: `DemoApiLatencyBudgetBurn`
**Objective**: 99% of requests to `/` answered in under 300ms, over 30 days.

## What it means

Requests slower than 300ms count as errors for this objective, even when they return 200. The SLI
is read straight from the histogram bucket `le="0.3"`, not from a percentile, so it is exact rather
than interpolated.

As for availability, a `critical` alert means the monthly budget would be gone within hours, and a
`warning` means a slow leak worth a ticket.

## Impact

The service answers, but slowly enough that callers notice or time out. Unlike a 500, this kind of
failure is invisible in logs that only record status codes.

## Confirm it

```bash
# Share of requests slower than 300ms, and the p95 for context
kubectl get --raw '/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=slo:sli_error:ratio_rate5m%7Bsloth_slo=%22latency%22%7D'
```

Open `demo-api / SLO` in Grafana and select the `latency` objective: the p95 and p99 curves are
shown against the 300ms line.

## Likely causes, in the order worth checking

1. **Injected latency still on.** `scripts/demo-traffic.sh status`.
2. **Not enough replicas for the traffic.** Look at requests per second against pod CPU:
   `kubectl top pods -n demo`.
3. **A slow dependency.** This demo API has none, which is itself the lesson: on a real service
   this is where a trace would tell you which call is slow.
4. **Noisy neighbours on the node**, visible in the Kubernetes compute dashboards.

## Mitigate

```bash
make demo-fix                                  # stop the injected latency
kubectl scale deployment/demo-api -n demo --replicas=4   # temporary relief only
```

Scaling by hand is a stopgap: it drifts from git, and Argo CD will revert it on the next sync.
The durable fix is a commit changing the replica count or the resource requests.

## Reproduce it on purpose

```bash
make demo-break RATE=0 LATENCY=400   # every request takes 400ms, over the 300ms objective
make demo-load SECONDS=120 RPS=8
make demo-fix
```

## Afterwards

Latency budgets are usually burned by a change, not by chance. Compare the start of the burn with
the last deployment in Argo CD before looking anywhere else.
