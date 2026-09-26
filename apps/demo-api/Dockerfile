# Built on Chainguard images, rebuilt daily from upstream sources: the scan that
# reported 22 unfixable findings on distroless and 159 on python:slim reports
# none here. See docs/adr/0011 for the measurements and the trade-offs.
#
# Both stages are pinned by digest to the same day's build. Chainguard's free
# tier only publishes `latest`, so the tag alone would move the Python version
# underneath us; the digest makes every move a Dependabot pull request, tested
# by CI, and keeps the build and runtime interpreters on the same version, which
# compiled dependencies (pydantic-core, uvloop) require.

FROM cgr.dev/chainguard/python:latest-dev@sha256:eb0d45dfc69fecb471d2eaee7a8eea281bf860578ef44cb85db1bfa8165c47fe AS build
USER root
WORKDIR /install
COPY requirements.txt .
# --target rather than --prefix: a flat directory with no python3.X in its path,
# so a Python version bump cannot silently break the import path below.
RUN pip install --no-cache-dir --target=/install/deps -r requirements.txt

FROM cgr.dev/chainguard/python:latest@sha256:565af762d7f3efedc4e60d7ac7815e41588211d3f5757be33d8303e915ee6c72
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
