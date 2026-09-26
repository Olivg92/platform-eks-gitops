# Dependencies are installed in a first stage, which has pip and a shell. The
# runtime image receives the result and nothing else.
FROM python:3.13-slim AS build
WORKDIR /install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install/deps -r requirements.txt

# Distroless: the Python interpreter and the libraries it links against, with no
# shell, no package manager and no pip. Measured against python:3.13-slim, this
# halves the high-severity findings (46 to 22) and cuts the image from 158 MB to
# 100 MB. See docs/adr/0011 for the numbers and the trade-off.
#
# Pinned by digest because distroless publishes no versioned tags; Dependabot
# raises the pull request when a new digest is published.
FROM gcr.io/distroless/python3-debian13@sha256:e866e2f9fbaa19f63e579cf2f61b7f76cd8a74c43a62a0af95d48678d9878436
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/deps/lib/python3.13/site-packages

COPY --from=build /install/deps /opt/deps
WORKDIR /app
COPY app ./app

# A numeric UID with no /etc/passwd entry: there is no shell to run useradd in,
# and none is needed. The Deployment pins the same UID.
USER 10001
EXPOSE 8000

# Kubernetes uses its own HTTP probes, but an image that can report its own
# health is also usable with docker run, and scanners expect it.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/usr/bin/python3", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/healthz', timeout=2).status == 200 else 1)"]

# Exec form, and the module rather than the uvicorn script: the script's shebang
# points at the interpreter of the build stage, which does not exist here.
ENTRYPOINT ["/usr/bin/python3", "-m", "uvicorn"]
CMD ["app.main:app", "--host", "0.0.0.0", "--port", "8000"]
