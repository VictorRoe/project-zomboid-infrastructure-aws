provider "aws" {
  region = var.aws_region
}

data "aws_ebs_snapshot_ids" "zomboid_snapshots" {
  owners = ["self"]

  filter {
    name   = "tag:Name"
    values = ["pz-world-data-snapshot"]
  }
}

data "aws_ebs_snapshot" "latest_zomboid_snapshot" {
  count       = length(data.aws_ebs_snapshot_ids.zomboid_snapshots.ids) > 0 ? 1 : 0
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = ["pz-world-data-snapshot"]
  }
}

# Canonical's Ubuntu Server 24.04 LTS image for the configured region.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  base_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
}

resource "aws_security_group" "pz_sg" {
  name        = "pz-server-sg"
  description = "Puertos requeridos para Project Zomboid"

  ingress {
    from_port   = 16261
    to_port     = 16262
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8766
    to_port     = 8766
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5. Instancia EC2 con script de User Data
resource "aws_instance" "pz_server" {
  ami                    = local.base_ami_id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [aws_security_group.pz_sg.id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "pz-world-data-root"
    }
  }


  user_data = <<-EOF
              #!/bin/bash
              set -e

              apt-get update -y
              apt-get install -y python3-pip git software-properties-common
              add-apt-repository --yes --update ppa:ansible/ansible
              apt-get install -y ansible

              mkdir -p /home/ubuntu/repo
              git clone https://github.com/VictorRoe/project-zomboid-infrastructure-aws.git /home/ubuntu/repo
              chown -R ubuntu:ubuntu /home/ubuntu/repo

              su - ubuntu -c "cd /home/ubuntu/repo/playbook && ansible-playbook -i inventory.ini project-zomboid-server-install.yml"
              EOF

  tags = {
    Name = "PZ-Server-Instance"
  }

  # The root disk holds the world: a new image must never replace a running
  # server implicitly. Rebuild deliberately with -replace after a backup.
  lifecycle {
    ignore_changes = [ami]
  }
}
