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

resource "aws_ebs_volume" "pz_data_volume" {
  availability_zone = var.availability_zone
  size              = 30
  type              = "gp3"

  snapshot_id = length(data.aws_ebs_snapshot.latest_zomboid_snapshot) > 0 ? data.aws_ebs_snapshot.latest_zomboid_snapshot[0].id : null

  tags = {
    Name = "pz-world-data"
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

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Esperar a que el volumen EBS secundario aparezca en el sistema
              until [ -b /dev/nvme1n1 ] || [ -b /dev/xvdf ] || [ -b /dev/sdb ]; do sleep 2; done

              DEVICE=$(lsblk -pn -o NAME | grep -v "$(lsblk -pn -o NAME,MOUNTPOINT | grep '/$' | awk '{print $1}')" | head -n 1)

              # Formatear solo si el volumen no tiene un sistema de archivos previo
              if ! blkid $DEVICE; then
                mkfs.ext4 $DEVICE
              fi

              # Crear directorio de persistencia y montar el disco
              mkdir -p /home/pzserver/Zomboid
              mount $DEVICE /home/pzserver/Zomboid

              # Agregar al fstab usando UUID para evitar problemas con nombres de dispositivos
              UUID=$(blkid -s UUID -o value $DEVICE)
              echo "UUID=$UUID /home/pzserver/Zomboid ext4 defaults,nofail 0 2" >> /etc/fstab

              # Instalar Ansible y dependencias
              apt-get update -y
              apt-get install -y python3-pip git software-properties-common
              add-apt-repository --yes --update ppa:ansible/ansible
              apt-get install -y ansible

              # Clonar y ejecutar el playbook
              mkdir -p /home/ubuntu/repo
              cd /home/ubuntu/repo
              git clone https://github.com/VictorRoe/project-zomboid-infrastructure-aws.git
              chown -R ubuntu:ubuntu /home/ubuntu/repo

              su - ubuntu -c "cd /home/ubuntu/repo/project-zomboid-infrastructure-aws/playbook && ansible-playbook -i inventory.ini project-zomboid-server-install.yaml"
              EOF

  tags = {
    Name = "PZ-Server-Instance"
  }
}

# 6. Vinculación del Volumen EBS
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.pz_data_volume.id
  instance_id = aws_instance.pz_server.id
}
