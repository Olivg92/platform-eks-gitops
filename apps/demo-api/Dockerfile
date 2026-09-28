# Built on Chainguard images, rebuilt daily from upstream sources: the scan that
# reported 22 unfixable findings on distroless and 159 on python:slim reports
# none here. See docs/adr/0011 for the measurements and the trade-offs.
#
# Both stages are pinned by digest to the same day's build. Chainguard's free
# tier only publishes `latest`, so the tag alone would move the Python version
# underneath us; the digest makes every move a deliberate change, tested by CI,
# and keeps the build and runtime interpreters on the same version, which
# compiled dependencies (pydantic-core, uvloop) require.
#
# Dependabot is configured to propose digest bumps, but its support for this
# registry's `latest` tags has been seen to stop silently. The image freshness
# workflow fails when that happens: see the update at the end of docs/adr/0011.

FROM cgr.dev/chainguard/python:latest-dev@sha256:87729167739190d9309588120a8ac0ffbf2eb95dd895abb9bada6bb9ecbf5a04 AS build
USER root
WORKDIR /install
COPY requirements.txt .
# --target rather than --prefix: a flat directory with no python3.X in its path,
# so a Python version bump cannot silently break the import path below.
RUN pip install --no-cache-dir --target=/install/deps -r requirements.txt

FROM cgr.dev/chainguard/python:latest@sha256:be59f7abb600892c78e6ff0fe1a8f39549da13302dc003c8a5eb1c14b03d995c
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/deps

COPY --from=build /install/deps /opt/deps
WORKDIR /app
COPY app ./app

# No shell and no package manager in this image, so no useradd: a numeric UID
# with no /etc/passwd entry works, and the Deployment pins the same one.
USER 10001
EXPOSE 8000

# Kubernetes uses its own HTTP probes, but an image that can report its own
# health is also usable with docker run, and scanners expect it.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/healthz', timeout=2).status == 200 else 1)"]

# The module rather than the uvicorn script, whose shebang would point at the
# build stage's interpreter.
ENTRYPOINT ["python", "-m", "uvicorn"]
CMD ["app.main:app", "--host", "0.0.0.0", "--port", "8000"]
