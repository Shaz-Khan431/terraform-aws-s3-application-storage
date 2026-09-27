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

# Ensures bucket logging is disabled if no access logging bucket is supplied
# count = 0 when no logging bucket is given, so aws_s3_bucket_logging.this is an empty list
run "bucket_logging_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging should be off unless access_log_bucket is set."
  }
}

# Ensures bucket logging is configured correctly, with the proper bucket, prefix, and EventTime partitioning
# A bucket was given, so count = 1 and the list has exactly one logging configuration.
# [0] selects that one item and every assertion below reads a different setting of the logging configuration.
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

# Intentionally setting the access logging bucket to the bucket being created, should expect a failure here
# The precondition in main.tf is what should be rejecting it. 
run "rejects_logging_to_itself" {
  command = plan

  variables {
    access_log_bucket = "claims-dev-remits-111122223333-us-east-1-an"
  }

  expect_failures = [aws_s3_bucket_logging.this]
}
