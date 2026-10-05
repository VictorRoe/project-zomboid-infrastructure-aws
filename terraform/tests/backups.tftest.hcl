# Offline: el provider de AWS está simulado.
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

# --- Snapshots automáticos hechos por la instancia, solo con ella prendida (#10) ---

run "enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_instance_profile.pz) == 1 && length(aws_iam_role_policy.snapshots) == 1
    error_message = "Por defecto la instancia tiene un rol para sus propios snapshots."
  }

  assert {
    condition     = one(aws_instance.pz_server.root_block_device).tags["pz-world-volume"] == "zomboid"
    error_message = "El disco del mundo tiene que llevar el tag que limita los permisos."
  }

  assert {
    condition = alltrue([
      strcontains(aws_instance.pz_server.user_data, "PZ_AUTO_SNAPSHOT_ENABLED=true"),
      strcontains(aws_instance.pz_server.user_data, "PZ_SNAPSHOT_TIME_UTC=09:00"),
      strcontains(aws_instance.pz_server.user_data, "PZ_SNAPSHOT_RETAIN=4"),
    ])
    error_message = "Por defecto: diario a las 09:00 UTC, se conservan 4."
  }
}

run "permissions_are_scoped" {
  command = plan

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.snapshots.statement :
      contains(st.actions, "ec2:DeleteSnapshot")
      && anytrue([for c in st.condition : c.variable == "aws:ResourceTag/pz-backup" && contains(c.values, "auto")])
      && anytrue([for c in st.condition : c.variable == "aws:ResourceTag/pz-server" && contains(c.values, "zomboid")])
    ])
    error_message = "La instancia solo puede borrar sus snapshots automáticos, nunca los manuales ni los de otro servidor."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.snapshots.statement :
      contains(st.actions, "ec2:CreateSnapshot") && anytrue([for c in st.condition : c.variable == "aws:ResourceTag/pz-world-volume" && contains(c.values, "zomboid")])
    ])
    error_message = "La instancia solo puede hacer snapshot de su disco del mundo."
  }

  assert {
    condition     = !anytrue([for st in data.aws_iam_policy_document.snapshots.statement : contains(st.actions, "ec2:*") || contains(st.actions, "*")])
    error_message = "Sin comodines de acciones."
  }
}

run "custom_schedule" {
  command = plan

  variables {
    backup_time_utc     = "05:30"
    backup_retain_count = 7
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "PZ_SNAPSHOT_TIME_UTC=05:30") && strcontains(aws_instance.pz_server.user_data, "PZ_SNAPSHOT_RETAIN=7")
    error_message = "Hora y retención tienen que ser configurables."
  }
}

run "disabled" {
  command = plan

  variables {
    auto_backup_enabled = false
  }

  assert {
    condition     = length(aws_iam_role.pz) == 0 && length(aws_iam_instance_profile.pz) == 0 && strcontains(aws_instance.pz_server.user_data, "PZ_AUTO_SNAPSHOT_ENABLED=false")
    error_message = "auto_backup_enabled = false no crea rol ni perfil y desactiva el timer."
  }

  assert {
    condition     = output.auto_backup == "desactivado"
    error_message = "El output tiene que informar que no hay snapshots automáticos."
  }
}

run "invalid_time_rejected" {
  command = plan

  variables {
    backup_time_utc = "9:00"
  }

  expect_failures = [var.backup_time_utc]
}

run "zero_retention_rejected" {
  command = plan

  variables {
    backup_retain_count = 0
  }

  expect_failures = [var.backup_retain_count]
}

run "restore_ignores_automatic_snapshots" {
  command = plan

  assert {
    condition     = anytrue([for f in data.aws_ebs_snapshot_ids.zomboid_snapshots.filter : f.name == "tag:Name" && toset(f.values) == toset(["pz-world-data-snapshot"])])
    error_message = "La restauración automática solo busca snapshots consistentes (Name=pz-world-data-snapshot)."
  }
}
