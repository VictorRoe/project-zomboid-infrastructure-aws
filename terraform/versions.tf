terraform {
  # 1.11: bloqueo nativo del backend S3 (use_lockfile) en versión estable.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
