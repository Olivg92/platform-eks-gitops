from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_index_is_healthy_by_default():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["message"] == "hello"


def test_probes():
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_metrics_are_exposed():
    body = client.get("/metrics").text
    assert "http_requests_total" in body
    assert "http_request_duration_seconds" in body


def test_injected_errors_are_returned():
    client.post("/chaos", json={"error_rate": 1.0, "latency_ms": 0})
    try:
        assert client.get("/").status_code == 500
    finally:
        client.post("/chaos", json={"error_rate": 0.0, "latency_ms": 0})


def test_injected_latency_is_applied():
    client.post("/chaos", json={"error_rate": 0.0, "latency_ms": 200})
    try:
        response = client.get("/")
        assert response.status_code == 200
        assert float(response.elapsed.total_seconds()) >= 0.2
    finally:
        client.post("/chaos", json={"error_rate": 0.0, "latency_ms": 0})


def test_chaos_settings_are_validated():
    assert client.post("/chaos", json={"error_rate": 2.0}).status_code == 422


def test_metrics_are_labelled_with_the_route_template():
    """The route is only known after the router has matched it: reading it too
    early labels every request as "unmatched" and makes the SLO queries empty."""
    client.get("/")
    body = client.get("/metrics").text
    assert 'route="/"' in body

    client.get("/no-such-page")
    body = client.get("/metrics").text
    assert 'route="unmatched"' in body
