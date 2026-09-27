locals {
  # <application>-<environment>-<purpose>-<account_id>-<region>-an
  # The -<account_id>-<region>-an suffix places the bucket in the account regional
  # namespace, so no other AWS account can ever create (or re-create) this name.
  bucket_name = "${var.application}-${var.environment}-${var.purpose}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"

  # tagging standards in one place where the caller cannot override the values
  standard_tags = {
    Application        = var.application
    Environment        = var.environment
    Purpose            = var.purpose
    DataClassification = var.data_classification
    ManagedBy          = "terraform"
    Module             = "application_storage"
  }

  # standard_tags is mentioned last to ensure that they cannot be overwritten by duplicate entries in var.tags
  tags = merge(var.tags, local.standard_tags)

  # null when versioning is off, so the expiration rule is only created for versioned buckets
  noncurrent_version_expiration_days = var.versioning_enabled ? var.noncurrent_version_expiration_days : null

  # KMS when a key is supplied, otherwise SSE-S3
  sse_algorithm = var.kms_key_arn == null ? "AES256" : "aws:kms"

  # caller statements, appended after the module's baseline statements in the bucket policy
  additional_policy_statements = var.additional_policy_json == null ? [] : jsondecode(var.additional_policy_json).Statement
}
