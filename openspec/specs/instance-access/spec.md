# instance-access Specification

## Purpose
Gives operators authenticated SSH access to the server and guarantees that backup snapshots are only taken after the game server has verifiably stopped.

## Requirements

### Requirement: Configurable SSH key pair
The stack SHALL attach a key pair to the instance when either `ssh_public_key` (a pair is created) or `ssh_key_name` (existing pair) is provided, and SHALL reject configurations that set both.

#### Scenario: Public key supplied
- **WHEN** `ssh_public_key` is set
- **THEN** a key pair is created and the instance's key name references it

#### Scenario: Existing key name
- **WHEN** `ssh_key_name = "ops"` is set
- **THEN** the instance's key name is `ops` and no key pair is created

#### Scenario: Both supplied
- **WHEN** both `ssh_public_key` and `ssh_key_name` are set
- **THEN** planning fails with a validation error

### Requirement: Restrictable SSH ingress
SSH ingress SHALL be limited to `ssh_allowed_cidrs`, defaulting to `0.0.0.0/0`.

#### Scenario: Restricted CIDR
- **WHEN** `ssh_allowed_cidrs = ["203.0.113.4/32"]`
- **THEN** the port 22 rule allows only that CIDR

### Requirement: Snapshot only after verified stop
The backup procedure SHALL stop the game service and confirm the game process has exited before creating a snapshot; if confirmation fails it SHALL exit non-zero without snapshotting or destroying, unless forced.

#### Scenario: Stop confirmed
- **WHEN** the service stops and no game process remains
- **THEN** the snapshot is created and destroy proceeds

#### Scenario: SSH unreachable
- **WHEN** the SSH connection fails
- **THEN** the script exits non-zero, no snapshot is created and `terraform destroy` is not run

#### Scenario: Forced
- **WHEN** stop cannot be confirmed and `FORCE_SNAPSHOT=1`
- **THEN** a warning is printed and the snapshot proceeds
