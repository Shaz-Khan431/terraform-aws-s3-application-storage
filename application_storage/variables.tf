# Bucket Naming Convention Standardization in form <app>-<env>-<purpose>-<account_id>-<account_region>-an
variable "application" {
  description = "Name of the application that owns the bucket, like claims. First segment of the bucket name."
  type        = string

  validation {
    # character length between 2-13 characters so that with the account/region suffix, the full name stays within S3's 63 character limit
    condition     = length(var.application) >= 2 && length(var.application) <= 13
    error_message = "application must be between 2 and 13 characters."
  }

  validation {
    # regex to ensure we adhere to S3 bucket name character rules
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.application))
    error_message = "application may only contain lowercase letters, numbers and hyphens, and must start and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment the bucket belongs to. Only options are dev / qa / uat / prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, uat, prod."
  }
}

variable "purpose" {
  description = "What the bucket holds, like exports. Lets one application own several buckets per environment."
  type        = string

  validation {
    # same length and character rules as application
    condition     = length(var.purpose) >= 2 && length(var.purpose) <= 13
    error_message = "purpose must be between 2 and 13 characters."
  }

  validation {
    # same regex as application
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.purpose))
    error_message = "purpose may only contain lowercase letters, numbers and hyphens, and must start and end with a letter or number."
  }
}

# To ensure that all buckets specify the data classification of their contents
variable "data_classification" {
  description = "Sensitivity of the data in the bucket. Only options are phi, confidential, or internal."
  type        = string

  validation {
    condition     = contains(["phi", "confidential", "internal"], var.data_classification)
    error_message = "data_classification must be one of: phi, confidential, internal."
  }
}

# Additional bucket tags if needed
variable "tags" {
  description = "Additional tags for the bucket. The module's standard tags (Application, Environment, Purpose, DataClassification, ManagedBy, Module) take precedence on conflicting keys."
  type        = map(string)
  default     = {}
}

# Versioning related variables
variable "versioning_enabled" {
  description = "Keep previous versions of objects when they are overwritten or deleted. Setting this to false on a bucket that was already versioned suspends versioning; S3 keeps existing versions until they expire."
  type        = bool
  default     = true
  nullable    = false
}

variable "noncurrent_version_expiration_days" {
  description = "Days to keep a previous object version before it is permanently deleted. Also applies after versioning is turned off, so versions kept from before still expire."
  type        = number
  default     = 90
  nullable    = false

  validation {
    # Must be >=1, and floor() rounds a float down to a whole number, because s3 only accepts whole days of 1 or more, then we equate the rounded down number to the variable. 
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number of at least 1."
  }
}

# Access logging variable(s)
variable "access_log_bucket" {
  description = "Name of an existing bucket to receive S3 server access logs. Must be in the same account and region, use SSE-S3 encryption, and allow the S3 logging service to write to it. Null disables access logging."
  type        = string
  default     = null # null = off, bucket name is the switch to turn it on
}

# KMS Key Support
variable "kms_key_arn" {
  description = "ARN of an existing customer managed KMS key for default encryption. Null uses SSE-S3 (AES256). Callers writing or reading objects need kms:GenerateDataKey and kms:Decrypt on the key."
  type        = string
  default     = null

  validation {
    # full key arn only because aliases can be repointed to a different key, and bare key IDs don't work across accounts
    condition = var.kms_key_arn == null ? true : (
      startswith(var.kms_key_arn, "arn:") && strcontains(var.kms_key_arn, ":key/")
    )
    error_message = "kms_key_arn must be a full KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not a key ID or alias."
  }
}

# Custom Bucket Policy Support
variable "additional_policy_json" {
  description = "Bucket policy JSON document whose statements are added after the module's baseline statements, e.g. built with jsonencode(). Statement must be a list."
  type        = string
  default     = null

  validation {
    # clear error at plan time instead of a jsondecode failure inside the module, ensuring the statements are structured in a list
    condition     = var.additional_policy_json == null ? true : can(tolist(jsondecode(var.additional_policy_json).Statement))
    error_message = "additional_policy_json must be a JSON policy document with a Statement list."
  }
}
