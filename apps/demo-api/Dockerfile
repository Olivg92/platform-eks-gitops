# Dependencies are installed in a first stage so the final image carries no
# build tooling and no pip cache.
FROM python:3.13-slim AS build
WORKDIR /install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install/deps -r requirements.txt

FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/deps/lib/python3.13/site-packages \
    PATH=/opt/deps/bin:$PATH

COPY --from=build /install/deps /opt/deps
WORKDIR /app
COPY app ./app

# Runs as an unprivileged user with no writable application directory, which is
# what the security checks in CI will expect.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin demo
USER 10001
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
