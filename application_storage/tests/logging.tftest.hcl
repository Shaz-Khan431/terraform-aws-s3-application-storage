# Plan-only tests against a mocked AWS provider so no credentials needed and nothing is created.
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

run "bucket_logging_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging should be off unless access_log_bucket is set."
  }
}

run "bucket_logging_on_with_partitioned_keys" {
  command = plan

  variables {
    access_log_bucket = "pbm-dev-s3-access-logs"
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "pbm-dev-s3-access-logs"
    error_message = "Logs should go to the given bucket."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_prefix == "s3-access-logs/"
    error_message = "Logs should use the fixed s3-access-logs/ prefix."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_object_key_format[0].partitioned_prefix[0].partition_date_source == "EventTime"
    error_message = "Log keys should be partitioned by event time."
  }
}

# The precondition in main.tf should reject a bucket that logs to itself
run "rejects_logging_to_itself" {
  command = plan

  variables {
    access_log_bucket = "claims-dev-remits-111122223333-us-east-1-an"
  }

  expect_failures = [aws_s3_bucket_logging.this]
}
