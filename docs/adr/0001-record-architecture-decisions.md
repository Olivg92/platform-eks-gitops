# 0001. Record architecture decisions

- **Status**: Accepted
- **Date**: 2026-09-18

## Context

This repository is a demo platform meant to be read by others. The code shows *what* was built,
but not *why* a given option was chosen over another, which is what matters most when reviewing
or extending a platform.

## Options considered

1. **No written decisions**: fastest, but the reasoning is lost and choices look arbitrary.
2. **Long design documents**: thorough, but heavy for a small project and rarely kept up to date.
3. **Architecture Decision Records** (Michael Nygard's format): one short Markdown file per decision, versioned with the code.

## Decision

Use lightweight ADRs in `docs/adr/`, numbered sequentially, based on [the template](0000-template.md).
Every non-trivial technical choice gets an ADR in the same pull request as the change.

## Consequences

- Reviewers can understand trade-offs in a few minutes without reading the code.
- Decisions are reviewed alongside the code that implements them.
- Accepted ADRs are immutable: changing a decision means writing a new ADR that supersedes the old one.
