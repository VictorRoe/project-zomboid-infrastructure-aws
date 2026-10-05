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

run "outputs_expose_operations_config" {
  command = plan

  variables {
    aws_region     = "sa-east-1"
    pz_server_name = "w1"
  }

  assert {
    condition     = output.aws_region == "sa-east-1" && output.pz_server_name == "w1"
    error_message = "La configuración de los scripts tiene que exponerse como outputs."
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "PZ_SERVER_NAME=w1")
    error_message = "El nombre del servidor tiene que pasarse al playbook."
  }
}

run "invalid_server_name_rejected" {
  command = plan

  variables {
    pz_server_name = "bad name;rm"
  }

  expect_failures = [var.pz_server_name]
}

# --- Revisión fija del repositorio (#18) ---

run "pinned_commit_by_default" {
  command = plan

  assert {
    condition = alltrue([
      strcontains(aws_instance.pz_server.user_data, "REPO_URL=https://github.com/VictorRoe/project-zomboid-infrastructure-aws.git"),
      strcontains(aws_instance.pz_server.user_data, "REPO_BRANCH=main"),
      strcontains(aws_instance.pz_server.user_data, "REPO_COMMIT=0123456789abcdef0123456789abcdef01234567"),
      strcontains(aws_instance.pz_server.user_data, "REPO_FOLLOW_BRANCH=false"),
    ])
    error_message = "Por defecto la instancia tiene que usar el commit fijo, no la punta de la rama."
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, filebase64("${path.module}/templates/pz-provision.sh"))
    error_message = "user_data tiene que instalar pz-provision tal cual está en el repo."
  }

  assert {
    condition     = output.repo_commit == "0123456789abcdef0123456789abcdef01234567"
    error_message = "repo_commit tiene que exponerse para pz-ctl.sh provision."
  }
}

run "missing_commit_rejected" {
  command = plan

  variables {
    repo_commit = ""
  }

  expect_failures = [var.repo_commit]
}

run "short_or_uppercase_commit_rejected" {
  command = plan

  variables {
    repo_commit = "ABCDEF1"
  }

  expect_failures = [var.repo_commit]
}

run "follow_branch_is_explicit_test_mode" {
  command = plan

  variables {
    repo_commit        = ""
    repo_follow_branch = true
    repo_branch        = "feat/x"
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "REPO_BRANCH=feat/x") && strcontains(aws_instance.pz_server.user_data, "REPO_FOLLOW_BRANCH=true")
    error_message = "repo_follow_branch tiene que seguir repo_branch de forma explícita."
  }

  assert {
    condition     = output.repo_commit == ""
    error_message = "En modo rama no hay commit fijo."
  }
}

run "follow_branch_with_commit_rejected" {
  command = plan

  variables {
    repo_follow_branch = true
  }

  expect_failures = [var.repo_commit]
}

run "invalid_branch_rejected" {
  command = plan

  variables {
    repo_branch = "main; rm -rf /"
  }

  expect_failures = [var.repo_branch]
}

run "local_vm_http_url_allowed" {
  command = plan

  variables {
    repo_url = "http://10.0.2.2:8730/repo.git"
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "REPO_URL=http://10.0.2.2:8730/repo.git")
    error_message = "La VM local clona por http desde el host (10.0.2.2)."
  }
}

run "other_http_url_rejected" {
  command = plan

  variables {
    repo_url = "http://example.com/repo.git"
  }

  expect_failures = [var.repo_url]
}

run "config_wait_passed_to_playbook" {
  command = plan

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "PZ_WAIT_FOR_CONFIG=true")
    error_message = "Por defecto el juego espera la configuración del operador."
  }
}
