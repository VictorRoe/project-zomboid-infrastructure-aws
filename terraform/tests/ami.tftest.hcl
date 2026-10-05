# Offline: el provider de AWS está simulado; no hacen falta credenciales ni llamadas a la API.
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
# Con SSH configurado, para que el aviso de check.ssh_access_for_operations no aparezca.
variables {
  repo_commit       = "0123456789abcdef0123456789abcdef01234567"
  ssh_key_name      = "ops"
  ssh_allowed_cidrs = ["203.0.113.4/32"]
}

override_data {
  target = data.aws_ami.ubuntu
  values = {
    id = "ami-lookup123"
  }
}

run "default_uses_region_lookup" {
  command = plan

  assert {
    condition     = aws_instance.pz_server.ami == "ami-lookup123"
    error_message = "Sin ami_id la instancia tiene que usar el resultado de la búsqueda de Ubuntu."
  }
}

run "override_wins" {
  command = plan

  variables {
    ami_id = "ami-override123"
  }

  assert {
    condition     = aws_instance.pz_server.ami == "ami-override123"
    error_message = "ami_id tiene que reemplazar la búsqueda."
  }
}

run "az_defaults_to_aws_choice" {
  command = plan

  variables {
    aws_region = "sa-east-1"
  }

  assert {
    condition     = var.availability_zone == null
    error_message = "availability_zone tiene que ser null por defecto para que AWS elija una en la región."
  }
}

run "mismatched_az_rejected" {
  command = plan

  variables {
    aws_region        = "sa-east-1"
    availability_zone = "us-east-1a"
  }

  expect_failures = [var.availability_zone]
}

# Los runs comparten estado: crear la instancia y después resolver otra imagen.
run "create_instance" {
  command = apply
}

run "new_image_does_not_replace_instance" {
  command = plan

  variables {
    ami_id = "ami-newer456"
  }

  assert {
    condition     = aws_instance.pz_server.ami == "ami-lookup123"
    error_message = "Un cambio de imagen no debe alterar (reemplazar) la instancia existente."
  }
}
