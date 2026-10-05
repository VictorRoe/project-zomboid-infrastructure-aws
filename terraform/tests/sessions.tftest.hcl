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

# --- Sesiones con stop/start y dirección estable (#9) ---

run "create" {
  command = apply

  assert {
    condition     = aws_eip.pz.instance == aws_instance.pz_server.id && aws_eip.pz.domain == "vpc"
    error_message = "La Elastic IP tiene que asociarse a la instancia."
  }

  assert {
    condition     = output.public_ip == aws_eip.pz.public_ip && output.instance_id == aws_instance.pz_server.id
    error_message = "public_ip tiene que ser la Elastic IP (estable) e instance_id tiene que exponerse para pz-ctl.sh."
  }
}

run "new_commit_does_not_touch_running_instance" {
  command = plan

  variables {
    repo_commit = "fedcba9876543210fedcba9876543210fedcba98"
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "REPO_COMMIT=0123456789abcdef0123456789abcdef01234567")
    error_message = "Un repo_commit nuevo no debe modificar (detener/reiniciar) la instancia: se aplica con pz-ctl.sh provision."
  }

  assert {
    condition     = output.repo_commit == "fedcba9876543210fedcba9876543210fedcba98"
    error_message = "El output repo_commit tiene que reflejar la revisión nueva para pz-ctl.sh provision."
  }
}
