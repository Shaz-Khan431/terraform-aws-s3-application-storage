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

run "default_outputs" {
  command = plan

  # Name is built in locals from values known at plan, and outputs.tf passes it through the
  # bucket resource. Checks the values are correct and, since no test uses override_during,
  # that both are known at plan time rather than (known after apply).
  assert {
    condition     = output.bucket_name == "claims-dev-remits-111122223333-us-east-1-an"
    error_message = "bucket_name output is wrong: ${output.bucket_name}"
  }

  assert {
    condition     = output.bucket_arn == "arn:aws:s3:::claims-dev-remits-111122223333-us-east-1-an"
    error_message = "bucket_arn output is wrong: ${output.bucket_arn}"
  }

  # Locals sets this value to AES256 if no kms_key_arn is provided, this test confirms that behavior.
  assert {
    condition     = output.encryption_algorithm == "AES256"
    error_message = "encryption_algorithm should be AES256 by default."
  }

  # Versioning enabled has its default set to true in variables, this test confirms that behavior
  assert {
    condition     = output.versioning_status == "Enabled"
    error_message = "versioning_status should be Enabled by default."
  }

  # Bucket's tag attribute is a map, so tomap() converts the output object to a map, then compares it to the tags applied to the created bucket
  assert {
    condition     = tomap(output.tags) == aws_s3_bucket.this.tags
    error_message = "tags output should match the tags applied to the bucket."
  }
}

# Ensures that the encryption algorithm is set to aws:kms when a key is provided, logic is in locals
# Ensures that when versioning is set to false, the value being passed is "Suspended" not "Disabled", logic is in main.tf
run "outputs_reflect_kms_and_suspended_versioning" {
  command = plan

  variables {
    kms_key_arn        = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    versioning_enabled = false
  }

  assert {
    condition     = output.encryption_algorithm == "aws:kms"
    error_message = "encryption_algorithm should be aws:kms when a key is given."
  }

  assert {
    condition     = output.versioning_status == "Suspended"
    error_message = "versioning_status should be Suspended when versioning is off."
  }
}
