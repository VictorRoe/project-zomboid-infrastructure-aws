# Offline: el provider de AWS está simulado.
mock_provider "aws" {
  # Valores que un mock no puede inventar con sentido: tipo de instancia y documentos IAM.
  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 8192, supported_architectures = ["x86_64"], burstable_performance_supported = false }
  }
  override_data {
    target = data.aws_iam_policy_document.dlm_assume
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_iam_policy_document.dlm
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }
  override_resource {
    target = aws_iam_role.dlm
    values = { arn = "arn:aws:iam::123456789012:role/pz-dlm-test" }
  }
}
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

# --- Snapshots automáticos con DLM (#10) ---

run "daily_policy_by_default" {
  command = plan

  assert {
    condition     = length(aws_dlm_lifecycle_policy.world) == 1 && aws_dlm_lifecycle_policy.world[0].state == "ENABLED"
    error_message = "La política diaria tiene que crearse por defecto."
  }

  assert {
    condition = (
      one(aws_dlm_lifecycle_policy.world[0].policy_details).target_tags == tomap({ "pz-world-volume" = "zomboid" })
      && one(aws_instance.pz_server.root_block_device).tags["pz-world-volume"] == "zomboid"
    )
    error_message = "La política tiene que apuntar solo al disco del mundo de este servidor, por tag."
  }

  assert {
    condition = (
      one(one(one(aws_dlm_lifecycle_policy.world[0].policy_details).schedule).create_rule).times == tolist(["09:00"])
      && one(one(one(aws_dlm_lifecycle_policy.world[0].policy_details).schedule).retain_rule).count == 7
    )
    error_message = "Por defecto: un snapshot diario a las 09:00 UTC y 7 copias."
  }

  assert {
    condition = (
      one(one(aws_dlm_lifecycle_policy.world[0].policy_details).schedule).tags_to_add["Name"] == "pz-world-data-snapshot-auto"
      && one(one(aws_dlm_lifecycle_policy.world[0].policy_details).schedule).tags_to_add["pz-consistency"] == "crash"
    )
    error_message = "Los automáticos no se declaran consistentes ni los elige la restauración automática."
  }
}

run "dlm_permissions_are_scoped" {
  command = plan

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.dlm.statement :
      contains(st.actions, "ec2:DeleteSnapshot") && anytrue([for c in st.condition : c.variable == "aws:ResourceTag/pz-backup" && contains(c.values, "auto")])
    ])
    error_message = "DLM solo puede borrar snapshots automáticos (pz-backup=auto), nunca los manuales."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.dlm.statement :
      contains(st.actions, "ec2:CreateSnapshot") && anytrue([for c in st.condition : c.variable == "aws:ResourceTag/pz-world-volume" && contains(c.values, "zomboid")])
    ])
    error_message = "DLM solo puede hacer snapshot de volúmenes de este servidor."
  }
}

run "custom_schedule" {
  command = plan

  variables {
    backup_time_utc     = "05:30"
    backup_retain_count = 14
    pz_server_name      = "w2"
  }

  assert {
    condition = (
      one(one(one(aws_dlm_lifecycle_policy.world[0].policy_details).schedule).create_rule).times == tolist(["05:30"])
      && one(one(one(aws_dlm_lifecycle_policy.world[0].policy_details).schedule).retain_rule).count == 14
      && one(aws_dlm_lifecycle_policy.world[0].policy_details).target_tags == tomap({ "pz-world-volume" = "w2" })
    )
    error_message = "Hora, retención y servidor tienen que ser configurables."
  }
}

run "disabled" {
  command = plan

  variables {
    backup_policy_enabled = false
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.world) == 0 && length(aws_iam_role.dlm) == 0 && output.backup_policy_id == ""
    error_message = "backup_policy_enabled = false no crea política ni rol."
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
