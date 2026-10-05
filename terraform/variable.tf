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
  default     = "m7i.large"
  description = "Tipo de instancia EC2 (x86_64, 2 vCPU/8 GiB no burstable por defecto). Tiene que tener al menos pz_java_xmx_mb + pz_host_overhead_mb de RAM"
}

variable "pz_java_xmx_mb" {
  type        = number
  default     = 4096
  description = "Heap máximo de Java del servidor (-Xmx, en MiB); Ansible lo escribe en ProjectZomboid64.json. Subirlo (y la instancia) para servidores con muchos mods"

  validation {
    condition     = var.pz_java_xmx_mb >= 1024 && floor(var.pz_java_xmx_mb) == var.pz_java_xmx_mb
    error_message = "pz_java_xmx_mb tiene que ser un entero >= 1024."
  }
}

variable "pz_host_overhead_mb" {
  type        = number
  default     = 3072
  description = "RAM (MiB) que se reserva además del heap: SO, memoria nativa de Java, pzsvrtool. La swap no cuenta"

  validation {
    condition     = var.pz_host_overhead_mb >= 1024 && floor(var.pz_host_overhead_mb) == var.pz_host_overhead_mb
    error_message = "pz_host_overhead_mb tiene que ser un entero >= 1024."
  }
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
  default     = []
  description = "Redes IPv4 administrativas (CIDR) autorizadas al puerto 22. Vacía = sin SSH"

  validation {
    condition = alltrue([
      for c in var.ssh_allowed_cidrs : can(cidrnetmask(c)) && can(cidrhost(c, 0)) && try(cidrhost(c, 0) == split("/", c)[0], false)
    ])
    error_message = "ssh_allowed_cidrs solo admite CIDRs IPv4 válidos con la dirección de red (p. ej. 203.0.113.4/32 o 198.51.100.0/24)."
  }

  validation {
    condition     = var.ssh_allow_any_source || alltrue([for c in var.ssh_allowed_cidrs : !endswith(c, "/0")])
    error_message = "ssh_allowed_cidrs no puede abrir SSH a todo Internet (/0); usar las redes administrativas. Excepción explícita: ssh_allow_any_source = true."
  }
}

variable "ssh_allow_any_source" {
  type        = bool
  default     = false
  description = "Excepción explícita: permite un CIDR /0 en ssh_allowed_cidrs (SSH expuesto a Internet)"
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

variable "pz_wait_for_config" {
  type        = bool
  default     = true
  description = "No iniciar el juego hasta que el operador suba la configuración (script/pz-ctl.sh push-config); evita crear el mundo con otro mapa"
}

variable "repo_url" {
  type        = string
  default     = "https://github.com/VictorRoe/project-zomboid-infrastructure-aws.git"
  description = "Repositorio que la instancia clona al arrancar para correr el playbook"

  validation {
    # http solo hacia el host de la VM local de pruebas (10.0.2.2 en QEMU), inalcanzable desde una EC2.
    condition     = can(regex("^(https://[A-Za-z0-9._/-]+|http://10\\.0\\.2\\.2:[0-9]+/[A-Za-z0-9._/-]+)$", var.repo_url))
    error_message = "repo_url tiene que ser una URL https sin espacios ni caracteres especiales."
  }
}

variable "repo_branch" {
  type        = string
  default     = "main"
  description = "Rama desde la que se obtiene repo_commit (o que se sigue con repo_follow_branch)"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.repo_branch))
    error_message = "repo_branch solo puede contener letras, dígitos, '.', '_', '/' y '-'."
  }
}

variable "repo_commit" {
  type        = string
  default     = ""
  description = "SHA completo (40 caracteres) del commit que ejecuta la instancia. Obligatorio salvo con repo_follow_branch"

  validation {
    condition     = var.repo_follow_branch ? var.repo_commit == "" : can(regex("^[0-9a-f]{40}$", var.repo_commit))
    error_message = "repo_commit tiene que ser el SHA completo (40 caracteres hex, minúsculas) de un commit integrado y probado. Para seguir una rama mutable en pruebas: repo_follow_branch = true y repo_commit vacío."
  }
}

variable "repo_follow_branch" {
  type        = bool
  default     = false
  description = "Modo de prueba explícito: seguir la punta mutable de repo_branch en lugar de un commit fijo"
}

variable "backup_policy_enabled" {
  type        = bool
  default     = true
  description = "Crear la política DLM de snapshots automáticos del disco del mundo"
}

variable "backup_time_utc" {
  type        = string
  default     = "09:00"
  description = "Hora UTC (HH:MM) del snapshot diario; DLM lo inicia dentro de la hora siguiente"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_time_utc))
    error_message = "backup_time_utc tiene que tener el formato HH:MM (UTC)."
  }
}

variable "backup_retain_count" {
  type        = number
  default     = 7
  description = "Cantidad de snapshots diarios automáticos que conserva DLM"

  validation {
    condition     = var.backup_retain_count >= 1 && var.backup_retain_count <= 1000 && floor(var.backup_retain_count) == var.backup_retain_count
    error_message = "backup_retain_count tiene que ser un entero entre 1 y 1000."
  }
}
