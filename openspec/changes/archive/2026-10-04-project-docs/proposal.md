# Proposal

## Why

The repo has a one-line README and no record of how the pieces fit together or why they are built this way. The five fix changes (issues #1–#5) need a place to record current state and decisions, and the project needs a changelog to keep releases readable.

## What Changes

- Add `docs/` in the maintainer's established convention:
  - `docs/architecture.md` — components, AWS resources, on-host layout, diagram.
  - `docs/flows.md` — provisioning, backup & destroy, auto-update, (later) restore and testing flows.
  - `docs/spec.md` — current target state (variables, ports, paths, services).
  - `docs/decisions.md` — numbered, dated decision log (D1…), each with why and consequences; seeded with the existing design decisions inferred from code.
  - `docs/operations.md` — day-to-day commands.
- Add `CHANGELOG.md` (Keep a Changelog format, `[Unreleased]` section).
- Commit `CLAUDE.md`; expand README to a short overview linking to `docs/`.
- Every subsequent change updates `docs/spec.md`, appends to `docs/decisions.md` and adds a `CHANGELOG.md` entry.

## Capabilities

### New Capabilities

### Modified Capabilities

No behavior changes — documentation only (`skip_specs: true`).

## Impact

Docs only: `docs/`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`. Base of the branch stack for the five fix changes.
