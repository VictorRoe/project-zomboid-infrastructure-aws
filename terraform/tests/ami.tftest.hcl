# Offline: the AWS provider is mocked, no credentials or API calls are needed.
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
    error_message = "Without ami_id the instance must use the Ubuntu lookup result."
  }
}

run "override_wins" {
  command = plan

  variables {
    ami_id = "ami-override123"
  }

  assert {
    condition     = aws_instance.pz_server.ami == "ami-override123"
    error_message = "ami_id must override the lookup."
  }
}

run "az_defaults_to_aws_choice" {
  command = plan

  variables {
    aws_region = "sa-east-1"
  }

  assert {
    condition     = var.availability_zone == null
    error_message = "availability_zone must default to null so AWS picks one in the region."
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

# Runs share state: create the instance, then resolve a different image.
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
    error_message = "An image change must not alter (replace) the existing instance."
  }
}
