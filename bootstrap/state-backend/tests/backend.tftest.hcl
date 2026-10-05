# Offline: el provider de AWS está simulado.
mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }
  # Un documento simulado devuelve texto aleatorio; la política real se verifica por sus argumentos.
  override_data {
    target = data.aws_iam_policy_document.tls_only
    values = { json = "{}" }
  }
}

run "secure_defaults" {
  command = apply

  assert {
    condition     = aws_s3_bucket.state.bucket == "pz-tfstate-123456789012-us-east-1"
    error_message = "El bucket por defecto tiene que incluir la cuenta y la región."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "El estado tiene que versionarse para poder recuperar una versión anterior."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "El estado tiene que cifrarse en reposo."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "El bucket del estado nunca puede ser público."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.tls_only.statement :
      st.effect == "Deny" && anytrue([for c in st.condition : c.variable == "aws:SecureTransport" && contains(c.values, "false")])
    ])
    error_message = "El bucket tiene que rechazar accesos sin TLS."
  }

  assert {
    condition     = output.backend_hcl == "bucket = \"pz-tfstate-123456789012-us-east-1\"\nregion = \"us-east-1\"\n"
    error_message = "backend_hcl tiene que dar el contenido de terraform/backend.hcl."
  }
}

run "short_retention_rejected" {
  command = plan

  variables {
    noncurrent_version_days = 1
  }

  expect_failures = [var.noncurrent_version_days]
}
