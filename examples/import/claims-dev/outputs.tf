output "bucket_name" {
  description = "Name of the application bucket."
  value       = module.storage.bucket_name
}

output "bucket_arn" {
  description = "ARN of the application bucket, for IAM policies."
  value       = module.storage.bucket_arn
}
