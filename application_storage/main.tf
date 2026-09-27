resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  # Name must end in -<account_id>-<region>-an; S3 rejects the create if either doesn't match the caller
  bucket_namespace = "account-regional"

  # Explicit rather than relying on the provider default: a bucket holding data can
  # never be deleted by Terraform, including when a naming input change forces replacement
  force_destroy = false

  tags = local.tags
}
