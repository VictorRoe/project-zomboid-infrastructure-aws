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

# Commit fijo de prueba (#18): repo_commit es obligatorio fuera del modo rama.
variables {
  repo_commit = "0123456789abcdef0123456789abcdef01234567"
}

override_data {
  target = data.aws_ami.ubuntu
  values = {
    id = "ami-base"
  }
}

# key_name es opcional+computado: sin valor es desconocido en el plan;
# por eso se verifica el local que lo alimenta.
run "no_key_by_default" {
  command = plan

  expect_failures = [check.ssh_access_for_operations]

  assert {
    condition     = local.key_name == null && length(aws_key_pair.pz) == 0
    error_message = "Sin variables SSH no se crea ni se asocia ningún key pair."
  }
}

run "public_key_creates_pair" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["203.0.113.4/32"]
    ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly ops@example"
  }

  assert {
    condition     = length(aws_key_pair.pz) == 1 && aws_instance.pz_server.key_name == "pz-server"
    error_message = "ssh_public_key tiene que crear el key pair pz-server y asociarlo."
  }
}

run "existing_key_name" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["203.0.113.4/32"]
    ssh_key_name      = "ops"
  }

  assert {
    condition     = aws_instance.pz_server.key_name == "ops" && length(aws_key_pair.pz) == 0
    error_message = "ssh_key_name tiene que asociarse sin crear un key pair."
  }
}

run "both_inputs_rejected" {
  command = plan

  variables {
    ssh_key_name   = "ops"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly ops@example"
  }

  expect_failures = [var.ssh_key_name]
}

# --- Ingreso SSH (#19) ---

run "no_ssh_ingress_by_default" {
  command = plan

  assert {
    condition     = !anytrue([for r in aws_security_group.pz_sg.ingress : r.from_port == 22])
    error_message = "Sin ssh_allowed_cidrs no tiene que haber regla para el puerto 22."
  }

  assert {
    condition = alltrue([
      anytrue([for r in aws_security_group.pz_sg.ingress : r.from_port == 16261 && r.to_port == 16262 && r.protocol == "udp"]),
      anytrue([for r in aws_security_group.pz_sg.ingress : r.from_port == 8766 && r.protocol == "udp"]),
    ])
    error_message = "Los puertos del juego no dependen de SSH."
  }

  assert {
    condition     = output.ssh_enabled == false
    error_message = "ssh_enabled tiene que avisar a los scripts que no hay SSH."
  }

  expect_failures = [check.ssh_access_for_operations]
}

run "ssh_ingress_restricted" {
  command = plan

  variables {
    ssh_key_name      = "ops"
    ssh_allowed_cidrs = ["203.0.113.4/32", "198.51.100.0/24"]
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.pz_sg.ingress :
      r.from_port == 22 && r.protocol == "tcp" && toset(r.cidr_blocks) == toset(["203.0.113.4/32", "198.51.100.0/24"])
    ])
    error_message = "El puerto 22 solo debe permitir ssh_allowed_cidrs."
  }

  assert {
    condition     = output.ssh_enabled == true
    error_message = "Con clave y redes administrativas, SSH queda habilitado."
  }
}

run "internet_wide_ssh_rejected" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.ssh_allowed_cidrs]
}

run "internet_wide_ssh_explicit_exception" {
  command = plan

  variables {
    ssh_key_name         = "ops"
    ssh_allowed_cidrs    = ["0.0.0.0/0"]
    ssh_allow_any_source = true
  }

  assert {
    condition     = anytrue([for r in aws_security_group.pz_sg.ingress : r.from_port == 22 && contains(r.cidr_blocks, "0.0.0.0/0")])
    error_message = "La excepción explícita tiene que permitir el /0."
  }
}

run "host_bits_rejected" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["203.0.113.4/24"]
  }

  expect_failures = [var.ssh_allowed_cidrs]
}

run "malformed_cidr_rejected" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["300.1.1.1/32"]
  }

  expect_failures = [var.ssh_allowed_cidrs]
}

run "bare_ip_rejected" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["203.0.113.4"]
  }

  expect_failures = [var.ssh_allowed_cidrs]
}

run "ipv6_rejected" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["2001:db8::/32"]
  }

  expect_failures = [var.ssh_allowed_cidrs]
}
