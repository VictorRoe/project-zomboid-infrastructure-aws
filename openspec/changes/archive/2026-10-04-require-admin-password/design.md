# Design

## Context

Playbook runs on the instance itself (`ansible_connection=local`) as `ubuntu` with `become: true`. Vars live inline in the play. pzsvrtool reads `pzRootAdminPassword` from its config file.

## Goals / Non-Goals

**Goals:** secure-by-default unattended runs; persistent credential; offline tests.

**Non-Goals:** Secrets Manager/SSM integration (needs IAM instance profile; possible follow-up); rotating the password of an already-created admin account inside the PZ database.

## Decisions

- **Generate on the host, persist on disk** over passing via user_data or Terraform `random_password` (both leak into metadata/state). The file lives on the root disk, so snapshot restore keeps it.
- **Generation:** `stat` file → if missing, `copy` content `lookup('ansible.builtin.password', '/dev/null', chars=['ascii_letters','digits'], length=32)` with `no_log`; then `slurp` + `set_fact pz_admin_password_effective` (`no_log`). A supplied password is also written to the file so the file is always the source of truth for operators.
- **Defaults:** `pz_admin_password: ""` (empty = generate). Validation (in `tasks/validate.yml`) only applies the strength rules when non-empty. The assert uses `quiet: true` instead of `no_log: true` so `fail_msg` is shown (assert output lists expressions, not values) — review finding.
- **Ordering:** `admin_password.yml` is included right after "Create pzsvrtool configuration directory" (needs the user and directory) and before "Configure pzsvrtool non-interactively".
- **Testability:** both task files are parameterized by `pz_user`/`pz_home`; `tests/ansible/test_admin_password.yml` runs them on localhost without become, `pz_user` = current user, `pz_home` = temp dir. A runner script asserts expected pass/fail exit codes and file mode/persistence.

## Risks / Trade-offs

- [PZ keeps the admin password in its DB after first start, so changing it later in config may not take effect] → documented in operations; out of scope.
- [Operator can't see the generated password without SSH] → SSH access added by `instance-ssh-access`; retrieval command printed in the playbook's final debug message (path only, not value).

## Migration Plan

Existing servers keep their current DB admin; on next playbook run a password file is created. Rollback: revert.
