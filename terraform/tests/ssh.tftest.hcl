# Offline: the AWS provider is mocked.
mock_provider "aws" {}

override_data {
  target = data.aws_ami.ubuntu
  values = {
    id = "ami-base"
  }
}

# key_name is optional+computed, so with no value it is unknown at plan time;
# assert on the local that feeds it instead.
run "no_key_by_default" {
  command = plan

  assert {
    condition     = local.key_name == null && length(aws_key_pair.pz) == 0
    error_message = "Without SSH inputs no key pair is created or attached."
  }
}

run "public_key_creates_pair" {
  command = plan

  variables {
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly ops@example"
  }

  assert {
    condition     = length(aws_key_pair.pz) == 1 && aws_instance.pz_server.key_name == "pz-server"
    error_message = "ssh_public_key must create the pz-server key pair and attach it."
  }
}

run "existing_key_name" {
  command = plan

  variables {
    ssh_key_name = "ops"
  }

  assert {
    condition     = aws_instance.pz_server.key_name == "ops" && length(aws_key_pair.pz) == 0
    error_message = "ssh_key_name must be attached without creating a key pair."
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

run "ssh_ingress_restricted" {
  command = plan

  variables {
    ssh_allowed_cidrs = ["203.0.113.4/32"]
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.pz_sg.ingress :
      r.from_port == 22 && toset(r.cidr_blocks) == toset(["203.0.113.4/32"])
    ])
    error_message = "Port 22 must only allow ssh_allowed_cidrs."
  }
}
