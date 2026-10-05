# Offline: el provider de AWS está simulado.
mock_provider "aws" {}

override_data {
  target = data.aws_ami.ubuntu
  values = {
    id = "ami-base"
  }
}

run "outputs_expose_backup_config" {
  command = plan

  variables {
    s3_bucket_name = "b1"
    aws_region     = "sa-east-1"
    pz_server_name = "w1"
  }

  assert {
    condition     = output.backup_bucket_name == "b1" && output.aws_region == "sa-east-1" && output.pz_server_name == "w1"
    error_message = "La configuración del backup tiene que exponerse como outputs para el script."
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "-e pz_server_name=w1")
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

run "repo_defaults" {
  command = plan

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "git clone --branch main https://github.com/VictorRoe/project-zomboid-infrastructure-aws.git")
    error_message = "Por defecto se tiene que clonar main del repositorio del proyecto."
  }
}

run "custom_branch" {
  command = plan

  variables {
    repo_branch = "feat/x"
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "git clone --branch feat/x") && strcontains(aws_instance.pz_server.user_data, "reset --hard origin/feat/x")
    error_message = "repo_branch tiene que usarse tanto al clonar como al actualizar."
  }
}

run "invalid_branch_rejected" {
  command = plan

  variables {
    repo_branch = "main; rm -rf /"
  }

  expect_failures = [var.repo_branch]
}
