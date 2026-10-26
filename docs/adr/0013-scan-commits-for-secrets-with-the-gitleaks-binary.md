# 0013. Scan the commits of a pull request for secrets, with the gitleaks binary

- **Status**: Accepted
- **Date**: 2026-10-26

## Context

CI runs every pre-commit hook with `pre-commit run --all-files`, gitleaks among them. The gitleaks
hook runs `gitleaks git --pre-commit --staged`: it reads what is staged, which is exactly right
before a commit. A CI checkout stages nothing, so in CI the hook read nothing and passed whatever
the branch held: a fake GitHub token committed to test it went through as `Passed`. The
README and [docs/ci.md](../ci.md) promised secrets detection on every pull request; nothing
delivered it.

What CI should read is the commits a pull request adds, not the files it ends with: a secret
added in one commit and deleted in the next is still in the history, and still public once pushed.
The hook stays as it is, since it does its job on a developer machine.

## Options considered

1. **`gitleaks/gitleaks-action`**, pinned by commit like every other action: Dependabot would bump
   it, and it works out the commit range by itself. But it is licensed under its own end-user
   agreement since v2, not an open-source licence, and asks for a licence key as soon as the
   repository belongs to an organisation. It runs gitleaks 8.24.3 unless told otherwise, not the
   version of the hook, and downloads it at run time without checking a checksum. It comments on
   pull requests by default, which needs a write permission this workflow does not grant.
2. **The gitleaks binary from its release**, checked against the checksum published with it, run
   with the commit range of the event: the same tool, version and command as on a developer
   machine. Dependabot does not see a version written in a `run` block, so it moves by hand,
   together with the hook.
3. **Run the hook differently in CI**, with `--from-ref` and `--to-ref`: pre-commit then picks the
   files the pull request changed, but the gitleaks hook takes no file names and still reads what
   is staged, which is still nothing.

## Decision

The `lint and security` job checks out the whole history and runs the gitleaks binary on the
commits of the pull request, from its base to its head; on a push to `main`, on the commits the
push brings, or on the whole history when there is no previous commit to start from. The archive
must match the sha256 written in the workflow before it runs, as an action must match its commit.
Its version is the hook's, 8.30.0, and moves with it. Findings are redacted, since CI logs of a
public repository are public.

## Consequences

- A secret in any commit of a pull request fails it, even if a later commit deletes it. That is
  the moment to rotate it, not to rewrite history, which cannot unpublish a pushed commit.
- The same scan runs locally, on a branch before pushing it:
  `gitleaks git --redact --log-opts="origin/main..HEAD"`.
- The checkout of this job fetches the whole history. On a repository of this size that costs a
  second or two.
- The gitleaks version is written twice, in the hook and in the workflow, and nothing bumps it:
  the workflow comment is the reminder. On a team repository, a check that the two agree would
  replace it.
