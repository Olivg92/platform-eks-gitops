# 0011. Ship the demo API on an image with no known vulnerabilities

- **Status**: Accepted
- **Date**: 2026-09-26

## Context

The first image scan in CI reported 159 findings. Read properly, none was critical, and almost none
could be fixed from this repository:

| Origin | Findings | High | Fixable |
|---|---|---|---|
| Debian 13 system packages, mostly util-linux, expat, ncurses | 154 | 44 | 0 |
| Libraries vendored inside pip (msgpack, setuptools) | 3 | 2 | 2 |

The fixable ones came from pip, which only the build stage needs. The rest waited on Debian. The
question was therefore not how to patch them, but which base image to start from.

## Options considered

Measured on the same application, with the same scanner, all severities:

| Runtime image | Total | Critical | High | Size | Shell |
|---|---|---|---|---|---|
| `python:3.13-slim` | 159 | 0 | 46 | 158 MB | yes |
| `gcr.io/distroless/python3-debian13` | 135 | 0 | 22 | 100 MB | no |
| `cgr.dev/chainguard/python` | **0** | 0 | 0 | 115 MB | no |

Distroless removes the shell and most system packages, but still ships Debian's Python 3.13.5 and
libraries, so it inherits their unfixed CVEs. Chainguard images are rebuilt daily from upstream
sources, so fixes land without waiting for a distribution release.

A third approach exists for when no clean image is available: triage each finding and record why
it does not apply, in a VEX document or a justified `.trivyignore`. On distroless the case was
solid (the util-linux CVEs are in `mount` and `nsenter`, absent from an image that only carries
`libuuid`; the tarfile, HTML and XML parser CVEs need input this API never accepts), but it is
manual work, redone for every new CVE. Removing the findings beats justifying them.

## Decision

Chainguard for both stages: `latest-dev` to install the dependencies, `latest` to run them.

Both are pinned by digest to the same day's build. The free tier only publishes `latest`, so the
tag alone would move the Python version underneath the build; the digest turns every move into a
Dependabot pull request, and keeps the build and runtime interpreters on the same version, which
compiled dependencies (pydantic-core, uvloop) require.

Two guards make the moving base safe:

- Dependencies are installed with `pip --target` into a flat directory, so no `python3.X` path is
  written anywhere a version bump could silently break.
- CI **starts the image** under the Deployment's constraints (UID 10001, read-only root filesystem,
  no capabilities) and checks that it answers. A clean scan proves an image has no known
  vulnerability, not that it works. Tested against a deliberately broken image: the check fails
  and prints the reason.

## Consequences

- Zero known vulnerabilities today, and a base that tends back towards zero on its own.
- Python 3.14 rather than 3.13, and CI tests on the same version as the runtime.
- **No shell in the container.** Debugging uses `make demo-debug`, which attaches an ephemeral
  container with its own tools. Tools are brought when needed, not shipped to every pod.
- A dependency on a vendor's free tier, whose terms changed once already. The exit is distroless,
  measured above and verified under the same constraints: a two-line change in the Dockerfile.
- "Zero" describes a date, not a property. New CVEs will be published; what changes is how fast
  the base image absorbs them.
