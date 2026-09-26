# 0011. Ship the demo API on a distroless image

- **Status**: Accepted
- **Date**: 2026-09-26

## Context

The first image scan in CI reported 159 findings on an image based on `python:3.13-slim`. The number
needed reading before acting on it:

| Origin | Findings | High | Fixable |
|---|---|---|---|
| Debian 13 system packages, mostly the util-linux family | 154 | 44 | 0 |
| Python libraries vendored inside pip (msgpack, setuptools) | 3 | 2 | 2 |

None was critical. The two fixable ones came from pip, which only the build stage needs. The 44
high-severity system findings had no fix: they wait on Debian, and nothing in this repository can
change that. What can change is how many packages the image carries in the first place.

## Options considered

Measured, same application, same scanner:

| Runtime image | Total | High | Size | Shell |
|---|---|---|---|---|
| `python:3.13-slim` | 159 | 46 | 158 MB | yes |
| `python:3.13-slim`, pip removed | 156 | 44 | 158 MB | yes |
| `gcr.io/distroless/python3-debian13` | 135 | 22 | 100 MB | no |

Alpine was not measured: its musl libc needs separate wheels for the compiled dependencies
(uvloop, httptools, pydantic-core), which trades a smaller image for a build that differs from
every other environment.

## Decision

Distroless for the runtime stage; the build stage stays on `python:3.13-slim`, which has pip and
a shell and never ships. The runtime image is pinned by digest, since distroless publishes no
versioned tags, and Dependabot raises the pull request when a new digest appears.

Verified under the Deployment's own constraints, UID 10001, read-only root filesystem and no
capabilities: the API answers, metrics are exposed, the image health check passes, and the chaos
script still works because it only needs the Python interpreter.

## Consequences

- Half the high-severity findings, a third less image, and no fixable finding left.
- **There is no shell in the container.** `kubectl exec -it ... sh` fails. Debugging uses
  `kubectl debug`, which attaches an ephemeral container with its own tools to the running pod.
  That is the practice worth having anyway: debugging tools are brought when needed, not shipped
  to every pod in case someone needs them.
- The Python patch version follows the distroless release rather than python.org, since the
  interpreter comes from Debian. The minor version, which is what compiled extensions depend on,
  matches the build stage.
- The remaining 22 findings are reported in the Security tab and do not fail the build: they have
  no fix, and a pipeline that is permanently red is a pipeline nobody reads.
