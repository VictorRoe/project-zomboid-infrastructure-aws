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
    error_message = "availability_zone must belong to aws_region (e.g. us-east-1a for us-east-1)."
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
  description = "Nombre del bucket S3 para almacenamiento de respaldos"
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
