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

  # Restore source: explicit snapshot > latest tagged snapshot > none.
  latest_snapshot_id  = length(data.aws_ebs_snapshot.latest_zomboid_snapshot) > 0 ? data.aws_ebs_snapshot.latest_zomboid_snapshot[0].id : ""
  restore_snapshot_id = !var.restore_from_snapshot ? "" : (var.restore_snapshot_id != "" ? var.restore_snapshot_id : local.latest_snapshot_id)
  restoring           = local.restore_snapshot_id != ""

  root_volume_size = local.restoring ? max(30, data.aws_ebs_snapshot.restore[0].volume_size) : 30
  instance_ami_id  = local.restoring ? aws_ami.restored[0].id : local.base_ami_id

  key_name = length(aws_key_pair.pz) > 0 ? aws_key_pair.pz[0].key_name : (var.ssh_key_name != "" ? var.ssh_key_name : null)

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    repo_url    = "https://github.com/VictorRoe/project-zomboid-infrastructure-aws.git"
    repo_branch = "main"
    repo_dir    = "/home/ubuntu/repo"
  })
}

data "aws_ebs_snapshot" "restore" {
  count        = local.restoring ? 1 : 0
  owners       = ["self"]
  snapshot_ids = [local.restore_snapshot_id]
}

# Image registered from the backup snapshot of the old root disk. Destroy
# deregisters it; the snapshot itself is not managed and stays.
resource "aws_ami" "restored" {
  count               = local.restoring ? 1 : 0
  name                = "pz-restore-${local.restore_snapshot_id}"
  root_device_name    = "/dev/sda1"
  virtualization_type = "hvm"
  ena_support         = true
  boot_mode           = "uefi-preferred"

  ebs_block_device {
    device_name           = "/dev/sda1"
    snapshot_id           = local.restore_snapshot_id
    volume_size           = local.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "pz-restore-${local.restore_snapshot_id}"
  }

  lifecycle {
    precondition {
      condition     = data.aws_ebs_snapshot.restore[0].state == "completed"
      error_message = "Snapshot ${local.restore_snapshot_id} is not completed yet; wait for it before restoring."
    }
  }
}

resource "aws_key_pair" "pz" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "pz-server"
  public_key = var.ssh_public_key
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
    cidr_blocks = var.ssh_allowed_cidrs
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
  ami                    = local.instance_ami_id
  instance_type          = var.instance_type
  availability_zone      = var.availability_zone
  vpc_security_group_ids = [aws_security_group.pz_sg.id]
  key_name               = local.key_name

  root_block_device {
    volume_size           = local.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "pz-world-data-root"
    }
  }


  user_data = local.user_data

  tags = {
    Name = "PZ-Server-Instance"
  }

  # The root disk holds the world: a new image must never replace a running
  # server implicitly. Rebuild deliberately with -replace after a backup.
  lifecycle {
    ignore_changes = [ami]
  }
}
