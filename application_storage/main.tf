resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  # Name must end in -<account_id>-<region>-an; S3 rejects the create if either doesn't match the caller
  bucket_namespace = "account-regional"

  # Explicit rather than relying on the provider default. A bucket holding data can
  # never be deleted by Terraform, including when a naming input change forces replacement
  force_destroy = false

  tags = local.tags
}

# Never public, at the bucket level as well as any account level setting
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs disabled so the bucket owner owns every object, and access is controlled only by IAM and the bucket policy
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }

    # S3 Bucket Keys cut KMS request cost, so if a kms key is provided, this value equates to true, enabling the bucket key.
    bucket_key_enabled = local.sse_algorithm == "aws:kms"

    # SSE-C lets an uploader encrypt with a key S3 never stores. It's blocked to prevent
    # ransomware that re-encrypts objects with an attacker's key
    blocked_encryption_types = ["SSE-C"]
  }
}
