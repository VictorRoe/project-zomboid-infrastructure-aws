# Offline: el provider de AWS está simulado.
mock_provider "aws" {}

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

  assert {
    condition     = local.key_name == null && length(aws_key_pair.pz) == 0
    error_message = "Sin variables SSH no se crea ni se asocia ningún key pair."
  }
}

run "public_key_creates_pair" {
  command = plan

  variables {
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly ops@example"
  }

  assert {
    condition     = length(aws_key_pair.pz) == 1 && aws_instance.pz_server.key_name == "pz-server"
    error_message = "ssh_public_key tiene que crear el key pair pz-server y asociarlo."
  }
}

run "existing_key_name" {
  command = plan

  variables {
    ssh_key_name = "ops"
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
    error_message = "El puerto 22 solo debe permitir ssh_allowed_cidrs."
  }
}
