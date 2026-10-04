# Offline: the AWS provider is mocked. A mocked aws_ebs_snapshot_ids returns
# no IDs, so "with snapshot" runs override every snapshot data source.
mock_provider "aws" {
  override_resource {
    target = aws_ami.restored
    values = {
      id = "ami-restored"
    }
  }
}

override_data {
  target = data.aws_ami.ubuntu
  values = {
    id = "ami-base"
  }
}

run "no_snapshot_fresh_install" {
  command = apply

  assert {
    condition     = aws_instance.pz_server.ami == "ami-base" && length(aws_ami.restored) == 0
    error_message = "Without a snapshot the base image must be used and nothing registered."
  }

  assert {
    condition     = output.restored_from_snapshot_id == ""
    error_message = "restored_from_snapshot_id must be empty on a fresh install."
  }
}

run "restore_disabled" {
  command = plan

  variables {
    restore_from_snapshot = false
  }

  override_data {
    target = data.aws_ebs_snapshot_ids.zomboid_snapshots
    values = { ids = ["snap-123"] }
  }
  override_data {
    target = data.aws_ebs_snapshot.latest_zomboid_snapshot[0]
    values = { id = "snap-123" }
  }

  assert {
    condition     = aws_instance.pz_server.ami == "ami-base" && length(aws_ami.restored) == 0
    error_message = "restore_from_snapshot = false must skip the restore."
  }
}

run "explicit_snapshot_wins" {
  command = plan

  variables {
    restore_snapshot_id = "snap-old"
  }

  override_data {
    target = data.aws_ebs_snapshot_ids.zomboid_snapshots
    values = { ids = ["snap-new"] }
  }
  override_data {
    target = data.aws_ebs_snapshot.latest_zomboid_snapshot[0]
    values = { id = "snap-new" }
  }
  override_data {
    target = data.aws_ebs_snapshot.restore[0]
    values = { id = "snap-old", state = "completed", volume_size = 40 }
  }

  assert {
    condition     = one(aws_ami.restored[0].ebs_block_device).snapshot_id == "snap-old"
    error_message = "restore_snapshot_id must take precedence over the latest snapshot."
  }

  assert {
    condition     = aws_instance.pz_server.root_block_device[0].volume_size == 40
    error_message = "The restored disk must be at least as large as the snapshot."
  }
}

run "pending_snapshot_rejected" {
  command = plan

  override_data {
    target = data.aws_ebs_snapshot_ids.zomboid_snapshots
    values = { ids = ["snap-pending"] }
  }
  override_data {
    target = data.aws_ebs_snapshot.latest_zomboid_snapshot[0]
    values = { id = "snap-pending" }
  }
  override_data {
    target = data.aws_ebs_snapshot.restore[0]
    values = { id = "snap-pending", state = "pending", volume_size = 30 }
  }

  expect_failures = [aws_ami.restored]
}

# Runs from here share state with the first apply above, which created a
# fresh instance. Use a separate state key for the restore lifecycle.
run "restore_from_latest" {
  command   = apply
  state_key = "restored"

  override_data {
    target = data.aws_ebs_snapshot_ids.zomboid_snapshots
    values = { ids = ["snap-123"] }
  }
  override_data {
    target = data.aws_ebs_snapshot.latest_zomboid_snapshot[0]
    values = { id = "snap-123" }
  }
  override_data {
    target = data.aws_ebs_snapshot.restore[0]
    values = { id = "snap-123", state = "completed", volume_size = 30 }
  }

  assert {
    condition     = aws_instance.pz_server.ami == "ami-restored"
    error_message = "The instance must boot from the image registered from the snapshot."
  }

  assert {
    condition     = one(aws_ami.restored[0].ebs_block_device).snapshot_id == "snap-123"
    error_message = "The registered image must be backed by the latest snapshot."
  }

  assert {
    condition     = output.restored_from_snapshot_id == "snap-123"
    error_message = "restored_from_snapshot_id must report the snapshot used."
  }

  assert {
    condition     = aws_ami.restored[0].ena_support && aws_ami.restored[0].root_device_name == "/dev/sda1"
    error_message = "The restored image must enable ENA and use /dev/sda1 as root."
  }
}

run "new_snapshot_does_not_roll_back_running_server" {
  command   = plan
  state_key = "restored"

  override_data {
    target = data.aws_ebs_snapshot_ids.zomboid_snapshots
    values = { ids = ["snap-456"] }
  }
  override_data {
    target = data.aws_ebs_snapshot.latest_zomboid_snapshot[0]
    values = { id = "snap-456" }
  }
  override_data {
    target = data.aws_ebs_snapshot.restore[0]
    values = { id = "snap-456", state = "completed", volume_size = 30 }
  }

  assert {
    condition     = aws_instance.pz_server.ami == "ami-restored"
    error_message = "A newer snapshot must not replace the running instance."
  }
}

run "user_data_updates_existing_checkout" {
  command = plan

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "runuser -u ubuntu -- git -C /home/ubuntu/repo fetch")
    error_message = "user_data must update an existing checkout as ubuntu instead of re-cloning."
  }
}
