# Bucket del estado remoto de terraform/. Es un stack aparte, con estado local propio
# (terraform.tfstate acá, ignorado por git), para que la baja del servidor nunca lo borre.
# Uso: ver docs/operations.md#estado-remoto-de-terraform.
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Región del bucket de estado"
}

variable "bucket_name" {
  type        = string
  default     = ""
  description = "Nombre del bucket; vacío = pz-tfstate-<cuenta>-<región>"
}

variable "noncurrent_version_days" {
  type        = number
  default     = 90
  description = "Días que se conservan las versiones anteriores del estado"

  validation {
    condition     = var.noncurrent_version_days >= 7
    error_message = "Conservar al menos 7 días de versiones anteriores del estado."
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "pz-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256): sin costo extra, a diferencia de una clave KMS propia.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "versiones-anteriores"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "bucket" {
  value       = aws_s3_bucket.state.bucket
  description = "Bucket del estado remoto"
}

output "backend_hcl" {
  value       = "bucket = \"${aws_s3_bucket.state.bucket}\"\nregion = \"${var.aws_region}\"\n"
  description = "Contenido de terraform/backend.hcl"
}
