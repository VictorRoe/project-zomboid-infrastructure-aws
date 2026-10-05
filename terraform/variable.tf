variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Región de AWS donde se desplegará la infraestructura"
}

variable "availability_zone" {
  type        = string
  default     = null
  description = "Zona de disponibilidad para la EC2 (null = AWS elige una dentro de aws_region)"

  validation {
    condition     = var.availability_zone == null || startswith(coalesce(var.availability_zone, "-"), var.aws_region)
    error_message = "availability_zone tiene que pertenecer a aws_region (p. ej. us-east-1a para us-east-1)."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.large"
  description = "Tipo de instancia EC2 para el servidor de Project Zomboid"
}

variable "s3_bucket_name" {
  type        = string
  default     = "zomboid-bucket-backup"
  description = "Bucket S3 existente para los metadatos de backup (no lo crea este stack: terraform destroy lo borraría)"
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "AMI explícita para la EC2; vacío = última Ubuntu 24.04 LTS de Canonical en aws_region"
}

variable "restore_from_snapshot" {
  type        = bool
  default     = true
  description = "Al crear la EC2, restaurar el disco desde el último snapshot pz-world-data-snapshot si existe"
}

variable "restore_snapshot_id" {
  type        = string
  default     = ""
  description = "Snapshot específico a restaurar; vacío = el último con tag pz-world-data-snapshot"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "Clave pública SSH; si se define, se crea el key pair pz-server y se asocia a la EC2"
}

variable "ssh_key_name" {
  type        = string
  default     = ""
  description = "Nombre de un key pair existente en AWS para la EC2 (excluyente con ssh_public_key)"

  validation {
    condition     = !(var.ssh_key_name != "" && var.ssh_public_key != "")
    error_message = "Definir ssh_public_key o ssh_key_name, no ambos."
  }
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs autorizados a conectarse por SSH (puerto 22)"
}

variable "pz_server_name" {
  type        = string
  default     = "zomboid"
  description = "Nombre del servidor/mundo de Project Zomboid (servicio pzsvrtool@<nombre>.service)"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.pz_server_name))
    error_message = "pz_server_name solo puede contener letras, dígitos, '.', '_' y '-'."
  }
}

variable "repo_url" {
  type        = string
  default     = "https://github.com/VictorRoe/project-zomboid-infrastructure-aws.git"
  description = "Repositorio que la instancia clona al arrancar para correr el playbook"

  validation {
    condition     = can(regex("^https://[A-Za-z0-9._/-]+$", var.repo_url))
    error_message = "repo_url tiene que ser una URL https sin espacios ni caracteres especiales."
  }
}

variable "repo_branch" {
  type        = string
  default     = "main"
  description = "Rama del repositorio que la instancia clona y actualiza al arrancar"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.repo_branch))
    error_message = "repo_branch solo puede contener letras, dígitos, '.', '_', '/' y '-'."
  }
}
