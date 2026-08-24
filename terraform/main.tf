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
  ami                    = "ami-0b6d9d3d33ba97d99" # Ubuntu Server
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

              su - ubuntu -c "cd /home/ubuntu/repo/playbook && ansible-playbook -i inventory.ini project-zomboid-server-install.yaml"
              EOF

  tags = {
    Name = "PZ-Server-Instance"
  }
}
