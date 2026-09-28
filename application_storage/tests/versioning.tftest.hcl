# Plan-only tests against a mocked AWS provider: no credentials needed and nothing is created.
# Terraform does not share mocks between test files, so each file declares its own.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  application         = "claims"
  environment         = "dev"
  purpose             = "remits"
  data_classification = "phi"
}

run "versioning_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled by default."
  }
}

# Lifecycle rules have no guaranteed order, so each assertion selects its rule by id
run "noncurrent_versions_expire_after_90_days" {
  command = plan

  assert {
    condition = one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.noncurrent_version_expiration[0].noncurrent_days
      if r.id == "expire-noncurrent-versions"
    ]) == 90
    error_message = "Noncurrent versions should expire after 90 days by default."
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.expiration[0].expired_object_delete_marker
      if r.id == "expire-noncurrent-versions"
    ]) == true
    error_message = "Expired delete markers should be cleaned up."
  }
}

run "incomplete_uploads_aborted_after_7_days" {
  command = plan

  assert {
    condition = one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.abort_incomplete_multipart_upload[0].days_after_initiation
      if r.id == "abort-incomplete-multipart-uploads"
    ]) == 7
    error_message = "Incomplete multipart uploads should be aborted after 7 days."
  }
}

run "custom_noncurrent_expiration" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 365
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.noncurrent_version_expiration[0].noncurrent_days
      if r.id == "expire-noncurrent-versions"
    ]) == 365
    error_message = "Custom noncurrent expiration should be used."
  }
}

# Suspending versioning keeps existing old versions, so the expiration rule must stay in place
run "versioning_off_suspends_and_still_expires" {
  command = plan

  variables {
    versioning_enabled                 = false
    noncurrent_version_expiration_days = 30
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "Turning versioning off should suspend it; Disabled is only valid for never-versioned buckets."
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.noncurrent_version_expiration[0].noncurrent_days
      if r.id == "expire-noncurrent-versions"
    ]) == 30
    error_message = "Versions kept from before versioning was suspended should still expire."
  }
}

run "rejects_zero_expiration_days" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

run "rejects_fractional_expiration_days" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 1.5
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}
