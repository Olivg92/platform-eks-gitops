"""A small API whose only purpose is to have an SLO.

It serves one endpoint that does trivial work, exposes Prometheus metrics, and
can be told to fail or to answer slowly. Injecting failures on demand is what
makes the error budget observable: without it, a demo platform is always green
and the interesting part, what happens when it is not, stays hidden.
"""

import asyncio
import os
import random
import time

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field

VERSION = os.getenv("APP_VERSION", "dev")

app = FastAPI(
    title="demo-api",
    version=VERSION,
    description="Demo workload used to demonstrate SLOs, burn-rate alerts and runbooks.",
)

# Labels stay low cardinality on purpose: the route template, never the raw path,
# and the status class rather than every individual code.
REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests processed",
    ["method", "route", "status"],
)
DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration",
    ["method", "route"],
    # Buckets chosen around the 300ms latency objective, so the SLI can be read
    # straight from the histogram without interpolation surprises.
    buckets=(0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.5, 5.0),
)
CHAOS_ERROR_RATE = Gauge("demo_chaos_error_rate", "Share of requests failed on purpose")
CHAOS_LATENCY = Gauge("demo_chaos_latency_seconds", "Extra latency added on purpose")


class Chaos(BaseModel):
    """How badly the API should misbehave."""

    error_rate: float = Field(0.0, ge=0.0, le=1.0, description="Share of requests answered with 500")
    latency_ms: int = Field(0, ge=0, le=10_000, description="Extra latency added to every request")


chaos = Chaos()
CHAOS_ERROR_RATE.set(chaos.error_rate)
CHAOS_LATENCY.set(chaos.latency_ms / 1000)


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    # The route is only known once the router downstream has matched it, so it
    # has to be read after the call, not before: reading it earlier labels every
    # single request as "unmatched".
    # Unmatched paths keep that shared label value, so a scanner hitting random
    # URLs cannot blow up the number of time series.
    label = getattr(request.scope.get("route"), "path", "unmatched")
    if label != "/metrics":
        DURATION.labels(request.method, label).observe(time.perf_counter() - start)
        REQUESTS.labels(request.method, label, str(response.status_code)).inc()
    return response


@app.get("/")
async def index():
    """The endpoint the SLO is about."""
    if chaos.latency_ms:
        await asyncio.sleep(chaos.latency_ms / 1000)
    if chaos.error_rate and random.random() < chaos.error_rate:
        return Response(content='{"detail":"injected failure"}', status_code=500, media_type="application/json")
    return {"message": "hello", "version": VERSION}


@app.get("/healthz")
async def healthz():
    """Liveness: the process is running. Never fails on purpose, or Kubernetes
    would restart the pod and hide the very failures we are demonstrating."""
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    """Readiness: the pod is willing to take traffic."""
    return {"status": "ready", "version": VERSION}


@app.get("/chaos", response_model=Chaos)
async def get_chaos():
    return chaos


@app.post("/chaos", response_model=Chaos)
async def set_chaos(settings: Chaos):
    """Inject failures or latency. See docs/runbooks for what the alerts look like."""
    global chaos
    chaos = settings
    CHAOS_ERROR_RATE.set(chaos.error_rate)
    CHAOS_LATENCY.set(chaos.latency_ms / 1000)
    return chaos


@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
