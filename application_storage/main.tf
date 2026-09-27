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

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    # Suspended rather than Disabled. S3 can't return a versioned bucket to Disabled,
    # so Suspended is the only "off" value that also works when turning versioning off later
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Always on since failed multipart uploads leave invisible, billed parts behind
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Always on, even with versioning off: suspending versioning keeps existing old versions,
  # so this rule still expires them. On a never-versioned bucket it simply has nothing to do.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    # Remove delete markers once no versions remain behind them
    expiration {
      expired_object_delete_marker = true
    }
  }

  # Versioning must be configured before rules that act on noncurrent versions
  depends_on = [aws_s3_bucket_versioning.this]
}

# Optional with "count", resource is only created when an access_log_bucket is given
resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = "s3-access-logs/"

  # Partitioned keys like <prefix>/<account_id>/<region>/<bucket>/YYYY/MM/DD/<file>
  # so many buckets can share one log bucket, and queries can filter by date.
  # EventTime files each record under the day the request happened, not when the log was delivered.
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }

  # Ensures the access log bucket is not the newly created bucket
  lifecycle {
    precondition {
      condition     = var.access_log_bucket != local.bucket_name
      error_message = "access_log_bucket can't be the bucket itself; logging to itself creates an endless loop of log files."
    }
  }
}
