variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Región de AWS donde se desplegará la infraestructura"
}

variable "availability_zone" {
  type        = string
  default     = "us-east-1a"
  description = "Zona de disponibilidad específica para la EC2 y el volumen EBS"
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
