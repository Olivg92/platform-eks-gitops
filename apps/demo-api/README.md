# demo-api

A deliberately small API whose purpose is to have an SLO worth watching.

| Endpoint | What it does |
|---|---|
| `GET /` | The endpoint the SLO is about: returns a JSON greeting |
| `GET /healthz` | Liveness probe. Never fails on purpose, so Kubernetes does not restart the pod during a demo |
| `GET /readyz` | Readiness probe |
| `GET /metrics` | Prometheus metrics: `http_requests_total`, `http_request_duration_seconds` |
| `GET /chaos` | Current failure injection settings |
| `POST /chaos` | Inject failures: `{"error_rate": 0.3, "latency_ms": 500}` |

Failure injection is the point: an error budget that never moves teaches nothing.
`POST /chaos` makes the SLI drop, the budget burn, and the alerts fire, on demand and reproducibly.

## Run it locally

```bash
pip install -r requirements-dev.txt
uvicorn app.main:app --reload
pytest
```

## Build the image for the local cluster

```bash
make demo-image      # from the repository root: builds and imports into k3d
```

## The image

The runtime image is distroless: the Python interpreter and its libraries, no shell, no pip,
100 MB. There is nothing to `kubectl exec` into; to debug a running pod, attach an ephemeral
container instead:

```bash
make demo-debug
```

It picks a running pod, since `kubectl debug` takes a pod and not a Deployment, and attaches a
busybox container that shares its process namespace. From there `ps` shows the API's processes,
and `/proc/1/root/app` is the application's filesystem. The debug container inherits the pod's
non-root UID, so it cannot do more than the application itself could.

See [ADR 0011](../../docs/adr/0011-distroless-runtime-image.md) for the measurements behind it.

Metric labels are kept low cardinality on purpose: the route template rather than the raw path,
so unmatched requests cannot create an unbounded number of time series.
