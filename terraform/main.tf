provider "aws" {
  region = var.aws_region
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

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

# Imagen Ubuntu Server 24.04 LTS de Canonical para la región configurada.
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

# RAM, arquitectura y CPU burstable del tipo elegido (lectura de la API, sin costo).
data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

locals {
  base_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id

  # Origen de la restauración: snapshot explícito > último snapshot con tag > ninguno.
  latest_snapshot_id  = length(data.aws_ebs_snapshot.latest_zomboid_snapshot) > 0 ? data.aws_ebs_snapshot.latest_zomboid_snapshot[0].id : ""
  restore_snapshot_id = !var.restore_from_snapshot ? "" : (var.restore_snapshot_id != "" ? var.restore_snapshot_id : local.latest_snapshot_id)
  restoring           = local.restore_snapshot_id != ""

  root_volume_size = local.restoring ? max(30, data.aws_ebs_snapshot.restore[0].volume_size) : 30
  instance_ami_id  = local.restoring ? aws_ami.restored[0].id : local.base_ami_id

  key_name    = length(aws_key_pair.pz) > 0 ? aws_key_pair.pz[0].key_name : (var.ssh_key_name != "" ? var.ssh_key_name : null)
  ssh_enabled = local.key_name != null && length(var.ssh_allowed_cidrs) > 0

  required_ram_mb = var.pz_java_xmx_mb + var.pz_host_overhead_mb

  # Tag que une el disco del mundo con la política DLM de este servidor (y solo de este).
  world_volume_tag = "pz-world-volume"

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    provision_script_b64 = filebase64("${path.module}/templates/pz-provision.sh")
    repo_url             = var.repo_url
    repo_branch          = var.repo_branch
    repo_commit          = var.repo_commit
    repo_follow_branch   = var.repo_follow_branch
    repo_dir             = "/home/ubuntu/repo"
    server_name          = var.pz_server_name
    java_xmx_mb          = var.pz_java_xmx_mb
    host_overhead_mb     = var.pz_host_overhead_mb
    wait_for_config      = var.pz_wait_for_config
  })
}

# Avisos de plan (no bloquean): el backup y los comandos de pz-ctl.sh necesitan SSH.
check "ssh_access_for_operations" {
  assert {
    condition     = local.ssh_enabled
    error_message = "Sin SSH configurado (ssh_public_key/ssh_key_name y ssh_allowed_cidrs): script/destroy-and-backup.sh y script/pz-ctl.sh stop/backup/push-config no van a poder detener el juego ni subir la configuración."
  }
}

check "burstable_cpu" {
  assert {
    condition     = !data.aws_ec2_instance_type.selected.burstable_performance_supported
    error_message = "${var.instance_type} es de CPU burstable (créditos): bajo carga sostenida se limita o cobra créditos extra. Documentar balance de créditos, modo y costo (ver docs/spec.md) o usar una familia no burstable."
  }
}

data "aws_ebs_snapshot" "restore" {
  count        = local.restoring ? 1 : 0
  owners       = ["self"]
  snapshot_ids = [local.restore_snapshot_id]
}

# Imagen registrada desde el snapshot de backup del disco raíz anterior. El destroy
# la desregistra; el snapshot no se gestiona acá y queda.
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
      error_message = "El snapshot ${local.restore_snapshot_id} todavía no está completo; esperar antes de restaurar."
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

  # Sin redes administrativas no hay regla de SSH.
  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [var.ssh_allowed_cidrs] : []
    content {
      description = "SSH administrativo"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ingress.value
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Instancia EC2 con script de User Data
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
      Name                     = "pz-world-data-root"
      (local.world_volume_tag) = var.pz_server_name
    }
  }

  user_data = local.user_data

  tags = {
    Name = "PZ-Server-Instance"
  }

  lifecycle {
    # El disco raíz contiene el mundo: ni una imagen nueva ni un user_data nuevo (p. ej.
    # otro repo_commit) deben reemplazar o reiniciar un servidor en marcha. Una instancia
    # nueva o restaurada usa los valores actuales; un host existente se actualiza con
    # `script/pz-ctl.sh provision`, y se reconstruye a propósito con -replace tras un backup.
    ignore_changes = [ami, user_data]

    precondition {
      condition     = contains(data.aws_ec2_instance_type.selected.supported_architectures, "x86_64")
      error_message = "${var.instance_type} no es x86_64; el playbook y pzsvrtool necesitan x86_64."
    }

    precondition {
      condition     = data.aws_ec2_instance_type.selected.memory_size >= local.required_ram_mb
      error_message = "${var.instance_type} tiene ${data.aws_ec2_instance_type.selected.memory_size} MiB de RAM y el servidor necesita al menos ${local.required_ram_mb} MiB (pz_java_xmx_mb + pz_host_overhead_mb)."
    }
  }
}

# Dirección pública estable entre stop/start. Se cobra por hora aunque la EC2 esté detenida.
resource "aws_eip" "pz" {
  domain   = "vpc"
  instance = aws_instance.pz_server.id

  tags = {
    Name = "pz-server-eip"
  }
}

# -----------------------------------------------------------------------------
# Snapshots automáticos del disco del mundo (DLM)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

# Permisos mínimos: snapshot solo de volúmenes con el tag de este servidor, y borrado
# solo de snapshots automáticos (pz-backup=auto); los manuales quedan fuera de su alcance.
data "aws_iam_policy_document" "dlm" {
  statement {
    sid       = "SnapshotWorldVolume"
    actions   = ["ec2:CreateSnapshot", "ec2:CreateSnapshots"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.world_volume_tag}"
      values   = [var.pz_server_name]
    }
  }

  statement {
    sid       = "CreateSnapshotResource"
    actions   = ["ec2:CreateSnapshot", "ec2:CreateSnapshots"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::snapshot/*"]
  }

  statement {
    sid       = "TagNewSnapshots"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::snapshot/*"]
  }

  statement {
    sid       = "DeleteOwnSnapshots"
    actions   = ["ec2:DeleteSnapshot"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::snapshot/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/pz-backup"
      values   = ["auto"]
    }
  }

  statement {
    sid       = "Describe"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeVolumes", "ec2:DescribeSnapshots"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "dlm" {
  count              = var.backup_policy_enabled ? 1 : 0
  name               = "pz-dlm-${var.pz_server_name}"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
}

resource "aws_iam_role_policy" "dlm" {
  count  = var.backup_policy_enabled ? 1 : 0
  name   = "pz-dlm-snapshots"
  role   = aws_iam_role.dlm[0].id
  policy = data.aws_iam_policy_document.dlm.json
}

resource "aws_dlm_lifecycle_policy" "world" {
  count              = var.backup_policy_enabled ? 1 : 0
  description        = "Snapshots diarios del mundo de PZ ${var.pz_server_name}"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      (local.world_volume_tag) = var.pz_server_name
    }

    schedule {
      name      = "diario"
      copy_tags = false

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = [var.backup_time_utc]
      }

      retain_rule {
        count = var.backup_retain_count
      }

      # Name distinto de pz-world-data-snapshot: la restauración automática solo usa los
      # snapshots consistentes (tomados con el juego detenido); estos se eligen a mano.
      tags_to_add = {
        Name             = "pz-world-data-snapshot-auto"
        "pz-backup"      = "auto"
        "pz-consistency" = "crash"
        "pz-server"      = var.pz_server_name
      }
    }
  }

  depends_on = [aws_iam_role_policy.dlm]
}
