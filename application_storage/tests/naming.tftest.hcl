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

# Ensures bucket naming convention is enforced, including the account regional namespace feature
run "bucket_name_follows_convention" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "claims-dev-remits-111122223333-us-east-1-an"
    error_message = "Bucket name should be <application>-<environment>-<purpose>-<account_id>-<region>-an, got ${aws_s3_bucket.this.bucket}."
  }

  assert {
    condition     = aws_s3_bucket.this.bucket_namespace == "account-regional"
    error_message = "Bucket should be created in the account regional namespace."
  }
}

# Ensure the bucket character limit restrictions successfully equate to 63 characters or less as needed,
# by testing the max character limit for "application" and "purpose" which is 13, and the longest possible region.
run "longest_name_fits_s3_limit" {
  command = plan

  override_data {
    target = data.aws_region.current
    values = { region = "ap-southeast-5" }
  }

  variables {
    application = "abcdefghijklm"
    environment = "prod"
    purpose     = "abcdefghijklm"
  }

  assert {
    condition     = length(aws_s3_bucket.this.bucket) <= 63
    error_message = "Longest possible name is ${length(aws_s3_bucket.this.bucket)} characters; S3 allows 63."
  }
}


# Ensures that the tags appended by the caller do not override the standard tagging
# Test intentionally attempts to override the Environment tag, which is set in the "environment" variable, not in the "tags" variable
# Ensures that if a new tag unrelated to the standards is added in the "tags" variable, that it appends successfully with no conflict
# Ensures that all standard tags are present
run "standard_tags_override_caller_tags" {
  command = plan

  variables {
    tags = {
      Environment = "production"
      Team        = "claims-eng"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Environment"] == "dev"
    error_message = "Caller tags must not override the standard Environment tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Team"] == "claims-eng"
    error_message = "Caller tags without a conflict should be kept."
  }

  assert {
    condition = alltrue([
      for key in ["Application", "Environment", "Purpose", "DataClassification", "ManagedBy", "Module"] :
      contains(keys(aws_s3_bucket.this.tags), key)
    ])
    error_message = "All six standard tags should be applied."
  }
}

# Regex and character limit tests for "application" variable
run "rejects_uppercase_application" {
  command = plan

  variables {
    application = "Claims"
  }

  expect_failures = [var.application]
}

run "rejects_leading_hyphen_in_application" {
  command = plan

  variables {
    application = "-claims"
  }

  expect_failures = [var.application]
}

run "rejects_trailing_hyphen_in_application" {
  command = plan

  variables {
    application = "claims-"
  }

  expect_failures = [var.application]
}

run "rejects_application_over_13_characters" {
  command = plan

  variables {
    application = "abcdefghijklmn"
  }

  expect_failures = [var.application]
}

run "rejects_application_under_2_characters" {
  command = plan

  variables {
    application = "c"
  }

  expect_failures = [var.application]
}

# Ensures "environment" variable adheres to the 4 only possible options
# dev / qa / uat / prod , enforcing naming convention standards
run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "production"
  }

  expect_failures = [var.environment]
}

# Regex and character limit tests for "purpose" variable
run "rejects_dot_in_purpose" {
  command = plan

  variables {
    purpose = "remits.v2"
  }

  expect_failures = [var.purpose]
}

run "rejects_purpose_under_2_characters" {
  command = plan

  variables {
    purpose = "r"
  }

  expect_failures = [var.purpose]
}

run "rejects_purpose_over_13_characters" {
  command = plan

  variables {
    purpose = "abcdefghijklmn"
  }

  expect_failures = [var.purpose]
}

# Ensures data classification tag adheres to the only 3 possible options
# phi / confidential / internal, enforcing tagging standards
run "rejects_unknown_data_classification" {
  command = plan

  variables {
    data_classification = "secret"
  }

  expect_failures = [var.data_classification]
}
