# demo-api is burning its availability error budget

**Alert**: `DemoApiAvailabilityBudgetBurn`
**Objective**: 99.5% of requests to `/` answered without a server error, over 30 days.

## What it means

The alert does not fire on an error rate, it fires on the *speed* at which the error budget is
being spent. Sloth generates two of them:

| Severity | Windows | Meaning |
|---|---|---|
| `critical` (page) | 5m and 1h, or 30m and 6h | The budget for the whole month would be gone in hours. Act now. |
| `warning` (ticket) | 2h and 1d, or 6h and 3d | A slow leak. It can wait for working hours, but it will not fix itself. |

Using two windows at once is what keeps it honest: the short window reacts fast, the long one
confirms the problem is not a thirty-second blip.

## Impact

Callers of `/` receive HTTP 500. With a 99.5% objective the monthly budget is about 3h36m of total
failure, so a critical burn rate of 14 exhausts it in roughly two days.

## Confirm it

```bash
# Current error ratio and burn rate
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  curl -s 'http://kube-prometheus-stack-prometheus:9090/api/v1/query?query=slo:current_burn_rate:ratio{sloth_service="demo-api"}'

# Which pods are failing
kubectl get pods -n demo -l app.kubernetes.io/name=demo-api
kubectl logs -n demo -l app.kubernetes.io/name=demo-api --tail=50
```

The `demo-api / SLO` dashboard in Grafana shows the same numbers, with the budget over time.

## Likely causes, in the order worth checking

1. **Failure injection left on.** This is a demo platform: check it first.
   `scripts/demo-traffic.sh status` shows what each pod is set to.
2. **A pod crash-looping or unready.** `kubectl get pods -n demo` and the events.
3. **A bad rollout.** Compare with the last Argo CD sync: `kubectl get app -n argocd demo-api`.
4. **The gateway or its backend.** If `/healthz` answers inside the cluster but requests fail from
   outside, look at the `HTTPRoute` and the Envoy Gateway pods instead of the application.

## Mitigate

```bash
make demo-fix                                   # stop the injected failures
kubectl rollout undo deployment/demo-api -n demo  # roll back a bad version
```

Rolling back means Argo CD will immediately restore the version declared in git, which is the point:
the fix belongs in a commit, not in the cluster.

## Reproduce it on purpose

```bash
make demo-break RATE=0.2      # 20% of requests fail, on every pod
make demo-load SECONDS=120 RPS=8
# the critical alert fires within a few minutes
make demo-fix
```

## Afterwards

The budget does not refill by rolling back: it recovers as the 30-day window moves on. If it went
negative, the honest next step is to slow down feature work until the service is stable again, which
is exactly what an error budget is for.
