output "bucket_name" {
  description = "Name of the bucket, for application configuration and SDK/CLI calls."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket, for IAM policies granting access. Known at plan time."
  value       = "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.this.bucket}"
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket. Can be used for things like CloudFront origins or region-specific endpoints."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "encryption_algorithm" {
  description = "Default encryption applied to objects: AES256 (SSE-S3) or aws:kms (SSE-KMS). With aws:kms, callers also need kms:GenerateDataKey and kms:Decrypt on the key."
  value       = local.sse_algorithm
}

output "versioning_status" {
  description = "Versioning state of the bucket: Enabled or Suspended."
  value       = aws_s3_bucket_versioning.this.versioning_configuration[0].status
}

output "tags" {
  description = "Tags applied to the bucket, including the module's standard tags."
  value       = local.tags
}
