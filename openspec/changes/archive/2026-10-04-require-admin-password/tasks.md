# Tasks

## 1. Validation

- [x] 1.1 Move variable validation to `playbook/tasks/validate.yml`, set `pz_admin_password: ""`, add strength rules (≥12, denylist, no whitespace/`=`) applied only when non-empty, `quiet: true` instead of `no_log`; verify `make ansible-check`
- [x] 1.2 Add `tests/ansible/` runner + test playbook covering weak, short, `=`/whitespace and strong passwords; verify `make ansible-test` passes

## 2. Generation and persistence

- [x] 2.1 Add `playbook/tasks/admin_password.yml` (generate if missing, persist 0600, slurp into effective fact, all `no_log`) and use the effective fact in `pzsvrtool.config`; verify tests for first-run generation (length ≥ 24, mode 0600) and reuse on second run
- [x] 2.2 Update final debug message with retrieval command (no value); verify a test run's output doesn't contain the password

## 3. Docs and changelog

- [x] 3.1 Update `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` where affected, append a dated decision entry to `docs/decisions.md`, and add an `[Unreleased]` entry to `CHANGELOG.md` referencing the issue; verify links resolve and values match the code
