# Offline: el provider de AWS está simulado; no hacen falta credenciales ni llamadas a la API.
mock_provider "aws" {}

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
