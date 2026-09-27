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
