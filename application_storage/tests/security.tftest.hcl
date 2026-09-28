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

run "public_access_fully_blocked" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings should be on."
  }
}

run "acls_disabled" {
  command = plan

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs should be disabled with BucketOwnerEnforced."
  }
}

run "force_destroy_off" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must be false so a bucket holding data can't be deleted by Terraform."
  }
}

run "sse_s3_by_default" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Default encryption should be SSE-S3 when no KMS key is given."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == false
    error_message = "Bucket Keys only apply to SSE-KMS."
  }
}

run "sse_kms_when_key_given" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Encryption should switch to SSE-KMS when a key is given."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "The supplied KMS key should be used."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == true
    error_message = "Bucket Keys should be on with SSE-KMS."
  }
}

# ["SSE-C"] written in code is a tuple; tolist() makes it comparable to the list attribute
run "sse_c_blocked" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).blocked_encryption_types == tolist(["SSE-C"])
    error_message = "SSE-C uploads should be blocked."
  }
}

run "policy_enforces_tls" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTLS"]
    error_message = "Bucket policy should contain only the two TLS statements by default."
  }

  assert {
    condition = alltrue([
      for st in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      st.Effect == "Deny" && st.Principal == "*"
    ])
    error_message = "TLS statements must be Deny for every principal."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "DenyInsecureTransport should match requests without TLS."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Condition.NumericLessThan["s3:TlsVersion"] == "1.2"
    error_message = "DenyOutdatedTLS should match TLS versions below 1.2."
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Resource == [
      "arn:aws:s3:::claims-dev-remits-111122223333-us-east-1-an",
      "arn:aws:s3:::claims-dev-remits-111122223333-us-east-1-an/*",
    ]
    error_message = "TLS statements should cover the bucket and every object in it."
  }
}

run "caller_statements_appended_after_baseline" {
  command = plan

  variables {
    additional_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "AllowReportingRead"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::444455556666:role/reporting" }
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::claims-dev-remits-111122223333-us-east-1-an/*"
      }]
    })
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTLS", "AllowReportingRead"]
    error_message = "Caller statements should be added after the TLS statements, never replace them."
  }
}

# Overrides the partition to ensure the bucket ARN always uses the partition from the aws_partition data source
run "govcloud_partition_in_policy" {
  command = plan

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws-us-gov" }
  }

  assert {
    condition     = startswith(jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Resource[0], "arn:aws-us-gov:s3:::")
    error_message = "Bucket ARN should use the current partition."
  }
}

run "rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111122223333:alias/claims"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_bare_kms_key_id" {
  command = plan

  variables {
    kms_key_arn = "1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_invalid_policy_json" {
  command = plan

  variables {
    additional_policy_json = "not json"
  }

  expect_failures = [var.additional_policy_json]
}

run "rejects_policy_without_statement_list" {
  command = plan

  variables {
    additional_policy_json = jsonencode({ Version = "2012-10-17", Statement = { Effect = "Allow" } })
  }

  expect_failures = [var.additional_policy_json]
}
