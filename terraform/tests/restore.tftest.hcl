# Offline: el provider de AWS está simulado. Un aws_ebs_snapshot_ids simulado no
# devuelve IDs, así que los runs "con snapshot" reemplazan cada data source de snapshot.
mock_provider "aws" {
  # Valores que un mock no puede inventar con sentido: tipo de instancia y documentos IAM.
  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 8192, supported_architectures = ["x86_64"], burstable_performance_supported = false }
  }
  override_data {
    target = data.aws_iam_policy_document.ec2_assume
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_iam_policy_document.snapshots
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }
  override_resource {
    target = aws_iam_role.pz
    values = { arn = "arn:aws:iam::123456789012:role/pz-server-test" }
  }
  override_resource {
    target = aws_ami.restored
    values = {
      id = "ami-restored"
    }
  }
}

# Commit fijo de prueba (#18): repo_commit es obligatorio fuera del modo rama.
# Con SSH configurado, para que el aviso de check.ssh_access_for_operations no aparezca.
variables {
  repo_commit       = "0123456789abcdef0123456789abcdef01234567"
  ssh_key_name      = "ops"
  ssh_allowed_cidrs = ["203.0.113.4/32"]
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
    error_message = "Sin snapshot se tiene que usar la imagen base y no registrar nada."
  }

  assert {
    condition     = output.restored_from_snapshot_id == ""
    error_message = "restored_from_snapshot_id tiene que estar vacío en una instalación nueva."
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
    error_message = "restore_from_snapshot = false tiene que omitir la restauración."
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
    error_message = "restore_snapshot_id tiene que tener prioridad sobre el último snapshot."
  }

  assert {
    condition     = aws_instance.pz_server.root_block_device[0].volume_size == 40
    error_message = "El disco restaurado tiene que ser al menos tan grande como el snapshot."
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

# Desde acá los runs compartirían estado con el primer apply, que creó una
# instancia nueva. Se usa otra state key para el ciclo de restauración.
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
    error_message = "La instancia tiene que arrancar desde la imagen registrada a partir del snapshot."
  }

  assert {
    condition     = one(aws_ami.restored[0].ebs_block_device).snapshot_id == "snap-123"
    error_message = "La imagen registrada tiene que estar respaldada por el último snapshot."
  }

  assert {
    condition     = output.restored_from_snapshot_id == "snap-123"
    error_message = "restored_from_snapshot_id tiene que informar el snapshot usado."
  }

  assert {
    condition     = aws_ami.restored[0].ena_support && aws_ami.restored[0].root_device_name == "/dev/sda1"
    error_message = "La imagen restaurada tiene que activar ENA y usar /dev/sda1 como raíz."
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
    error_message = "Un snapshot más nuevo no debe reemplazar la instancia en marcha."
  }
}

run "user_data_runs_provision_on_restored_disk" {
  command = plan

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "REPO_DIR=/home/ubuntu/repo") && strcontains(aws_instance.pz_server.user_data, "/usr/local/sbin/pz-provision")
    error_message = "user_data tiene que delegar en pz-provision, que actualiza un checkout existente (tests/provision)."
  }
}
