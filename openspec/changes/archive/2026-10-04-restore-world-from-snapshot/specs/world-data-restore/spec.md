# Spec Delta

## Purpose

Ensures a re-provisioned Project Zomboid server comes back with the world and configuration captured by the last backup, instead of starting empty.

## ADDED Requirements

### Requirement: Restore from latest backup snapshot
When a server instance is created, restore is enabled and at least one owned snapshot tagged `pz-world-data-snapshot` exists, the server SHALL boot from a disk created from the most recent such snapshot, sized at least as large as the snapshot.

#### Scenario: Snapshot exists
- **WHEN** the stack is applied and a tagged snapshot `snap-123` is the most recent
- **THEN** the instance boots from an image backed by `snap-123`
- **AND** the `restored_from_snapshot_id` output equals `snap-123`

### Requirement: Fresh install without snapshot
When no tagged snapshot exists or restore is disabled, the server SHALL boot from the base Ubuntu image and perform a fresh install.

#### Scenario: No snapshot
- **WHEN** the stack is applied and no tagged snapshot exists
- **THEN** the instance uses the base image and `restored_from_snapshot_id` is empty

#### Scenario: Restore disabled
- **WHEN** a tagged snapshot exists and `restore_from_snapshot = false`
- **THEN** the instance uses the base image and no restored image is registered

### Requirement: Restore a specific snapshot
The stack SHALL accept `restore_snapshot_id`; when non-empty and restore is enabled, that snapshot SHALL be used instead of the latest tagged one.

#### Scenario: Explicit snapshot
- **WHEN** `restore_snapshot_id = "snap-old"` while `snap-new` is the latest tagged snapshot
- **THEN** the instance boots from an image backed by `snap-old`

### Requirement: Idempotent first boot on restored disk
Provisioning SHALL succeed on a restored disk that already contains the repository checkout and an installed server, without reinstalling the game or deleting world data.

#### Scenario: Repo already present
- **WHEN** the boot script runs and `/home/ubuntu/repo` already exists
- **THEN** it updates the checkout instead of failing on clone and re-runs the playbook

### Requirement: Running server is never rolled back
A newer or different snapshot appearing SHALL NOT replace an existing server instance.

#### Scenario: Snapshot appears while server runs
- **WHEN** the instance exists and a new tagged snapshot is created
- **THEN** a subsequent plan shows no replacement of the instance

### Requirement: Only completed snapshots are restored
Restore SHALL refuse a snapshot that is not in the completed state, failing at plan/apply with a clear error.

#### Scenario: Snapshot pending
- **WHEN** the chosen snapshot's state is `pending`
- **THEN** the run fails with an error naming the snapshot
