# admin-credentials Specification

## Purpose
Ensures every provisioned Project Zomboid server has a strong, persistent root admin password that is never a shared default.

## Requirements

### Requirement: No default admin password
Provisioning SHALL NOT configure a fixed default admin password. When no password is supplied, a random password of at least 24 alphanumeric characters SHALL be generated.

#### Scenario: Unattended first run
- **WHEN** the playbook runs without `pz_admin_password`
- **THEN** a random password is generated, written to the admin password file with mode 0600 owned by the server user, and used in the pzsvrtool config

### Requirement: Generated password persists
A previously generated password SHALL be reused on subsequent runs rather than regenerated.

#### Scenario: Re-run on restored disk
- **WHEN** the admin password file already exists and no password is supplied
- **THEN** the existing password is used unchanged

### Requirement: Supplied password strength
A supplied password SHALL be rejected, failing the run before any host changes, if it is shorter than 12 characters, matches a known weak value, or contains whitespace or `=`.

#### Scenario: Weak value
- **WHEN** `pz_admin_password=test` is supplied
- **THEN** the run fails during validation with a message explaining the rule

#### Scenario: Strong value
- **WHEN** a 16-character password without whitespace or `=` is supplied
- **THEN** validation passes and that password is used and written to the admin password file

### Requirement: Secret hygiene
The admin password SHALL NOT appear in task output, Terraform state or instance user data.

#### Scenario: Log output
- **WHEN** the playbook runs with default verbosity
- **THEN** no task output contains the password value
