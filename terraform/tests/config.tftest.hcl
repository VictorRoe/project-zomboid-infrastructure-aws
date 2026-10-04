# Offline: the AWS provider is mocked.
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
    error_message = "Backup configuration must be exposed as outputs for the script."
  }

  assert {
    condition     = strcontains(aws_instance.pz_server.user_data, "-e pz_server_name=w1")
    error_message = "The server name must be passed to the playbook."
  }
}

run "invalid_server_name_rejected" {
  command = plan

  variables {
    pz_server_name = "bad name;rm"
  }

  expect_failures = [var.pz_server_name]
}
