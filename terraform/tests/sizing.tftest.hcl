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

# --- Tiers y dimensionamiento (#7) ---

run "default_tier_is_estandar" {
  command = plan

  assert {
    condition = (
      aws_instance.pz_server.instance_type == "m7i.large" && local.required_ram_mb == 7168
      && one(aws_instance.pz_server.root_block_device).volume_size == 30
      && output.tier.tier == "estandar"
    )
    error_message = "Por defecto: tier estandar (m7i.large, heap 4096 + 3072, 30 GB)."
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "PZ_JAVA_XMX_MB=4096") && strcontains(aws_instance.pz_server.user_data, "PZ_HOST_OVERHEAD_MB=3072")
    error_message = "El heap y el margen del tier tienen que llegar al playbook."
  }
}

run "tier_minimo" {
  command = plan

  variables {
    tier = "minimo"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 4096, supported_architectures = ["x86_64"], burstable_performance_supported = true }
  }

  assert {
    condition     = aws_instance.pz_server.instance_type == "t3.medium" && strcontains(aws_instance.pz_server.user_data, "PZ_JAVA_XMX_MB=2048") && local.required_ram_mb == 3584
    error_message = "minimo: t3.medium con heap 2048 + 1536."
  }

  # Burstable: el aviso es lo esperado en este tier.
  expect_failures = [check.burstable_cpu]
}

run "tier_robusto" {
  command = plan

  variables {
    tier = "robusto"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 16384, supported_architectures = ["x86_64"], burstable_performance_supported = false }
  }

  assert {
    condition     = aws_instance.pz_server.instance_type == "r7i.large" && strcontains(aws_instance.pz_server.user_data, "PZ_JAVA_XMX_MB=8192") && one(aws_instance.pz_server.root_block_device).volume_size == 50
    error_message = "robusto: r7i.large, heap 8192, 50 GB."
  }
}

run "tier_grande" {
  command = plan

  variables {
    tier = "grande"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 16384, supported_architectures = ["x86_64"], burstable_performance_supported = false }
  }

  assert {
    condition     = aws_instance.pz_server.instance_type == "m7i.xlarge" && strcontains(aws_instance.pz_server.user_data, "PZ_JAVA_XMX_MB=10240") && one(aws_instance.pz_server.root_block_device).volume_size == 60
    error_message = "grande: m7i.xlarge, heap 10240, 60 GB."
  }
}

run "explicit_variables_override_tier" {
  command = plan

  variables {
    tier                = "robusto"
    instance_type       = "m7i.xlarge"
    root_volume_size_gb = 80
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 16384, supported_architectures = ["x86_64"], burstable_performance_supported = false }
  }

  assert {
    condition = (
      aws_instance.pz_server.instance_type == "m7i.xlarge"
      && one(aws_instance.pz_server.root_block_device).volume_size == 80
      && strcontains(aws_instance.pz_server.user_data, "PZ_JAVA_XMX_MB=8192")
    )
    error_message = "Una variable explícita gana sobre el tier; el resto sale del tier."
  }
}

run "unknown_tier_rejected" {
  command = plan

  variables {
    tier = "enorme"
  }

  expect_failures = [var.tier]
}

run "insufficient_ram_rejected" {
  command = plan

  variables {
    pz_java_xmx_mb = 16384
  }

  expect_failures = [aws_instance.pz_server]
}

run "tier_on_too_small_instance_rejected" {
  command = plan

  variables {
    tier          = "robusto"
    instance_type = "m7i.large"
  }

  expect_failures = [aws_instance.pz_server]
}

run "arm_rejected" {
  command = plan

  variables {
    instance_type = "m7g.large"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 8192, supported_architectures = ["arm64"], burstable_performance_supported = false }
  }

  expect_failures = [aws_instance.pz_server]
}

run "burstable_warns" {
  command = plan

  variables {
    instance_type = "t3.large"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 8192, supported_architectures = ["x86_64"], burstable_performance_supported = true }
  }

  expect_failures = [check.burstable_cpu]
}

run "heap_too_small_rejected" {
  command = plan

  variables {
    pz_java_xmx_mb = 512
  }

  expect_failures = [var.pz_java_xmx_mb]
}

run "disk_too_small_rejected" {
  command = plan

  variables {
    root_volume_size_gb = 10
  }

  expect_failures = [var.root_volume_size_gb]
}

run "restore_keeps_tier_disk_if_larger" {
  command = plan

  variables {
    tier = "robusto"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 16384, supported_architectures = ["x86_64"], burstable_performance_supported = false }
  }
  override_data {
    target = data.aws_ebs_snapshot_ids.zomboid_snapshots
    values = { ids = ["snap-1"] }
  }
  override_data {
    target = data.aws_ebs_snapshot.latest_zomboid_snapshot[0]
    values = { id = "snap-1" }
  }
  override_data {
    target = data.aws_ebs_snapshot.restore[0]
    values = { id = "snap-1", state = "completed", volume_size = 30 }
  }

  assert {
    condition     = local.root_volume_size == 50
    error_message = "Al restaurar un snapshot más chico se usa el disco del tier."
  }
}
