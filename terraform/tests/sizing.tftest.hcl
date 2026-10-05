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

# --- Dimensionamiento (#7) ---

run "default_profile_fits" {
  command = plan

  assert {
    condition     = aws_instance.pz_server.instance_type == "m7i.large" && local.required_ram_mb == 7168
    error_message = "El perfil por defecto (m7i.large, heap 4096 + 3072 de margen) tiene que entrar."
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "PZ_JAVA_XMX_MB=4096") && strcontains(aws_instance.pz_server.user_data, "PZ_HOST_OVERHEAD_MB=3072")
    error_message = "El heap y el margen tienen que llegar al playbook."
  }
}

run "insufficient_ram_rejected" {
  command = plan

  variables {
    instance_type  = "r7i.large"
    pz_java_xmx_mb = 16384
  }

  expect_failures = [aws_instance.pz_server]
}

run "small_instance_rejected" {
  command = plan

  variables {
    instance_type = "t3.medium"
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 4096, supported_architectures = ["x86_64"], burstable_performance_supported = true }
  }

  expect_failures = [aws_instance.pz_server, check.burstable_cpu]
}

run "heavy_profile_example" {
  command = plan

  variables {
    instance_type  = "r7i.large"
    pz_java_xmx_mb = 8192
  }

  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { memory_size = 16384, supported_architectures = ["x86_64"], burstable_performance_supported = false }
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "PZ_JAVA_XMX_MB=8192")
    error_message = "Un perfil con muchos mods sube heap e instancia juntos."
  }
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
