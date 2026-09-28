provider "aws" {
  region = "us-east-1"

  # Organization-wide tags belong here, not in the module's tags input
  default_tags {
    tags = {
      CostCenter = "cc-1042"
      Owner      = "claims-platform"
    }
  }
}

# Same PHI settings as dev with the default 90-day retention, plus cross-account read for reporting
module "storage" {
  # Consumers outside this repo pin a release tag:
  # source = "git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git//application_storage?ref=application_storage/v0.1.0"
  source = "../../../application_storage"

  application         = "claims"
  environment         = "qa"
  purpose             = "remits"
  data_classification = "phi"

  kms_key_arn       = "arn:aws:kms:us-east-1:111122223333:key/5678efgh-56ef-78gh-90ij-567890abcdef"
  access_log_bucket = "pbm-qa-s3-access-logs"

  # The reporting team reads remittance files from its own account. The resource is this
  # bucket's ARN, following the module's naming convention (replace the account and region).
  additional_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowReportingRead"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::444455556666:role/claims-reporting" }
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::claims-qa-remits-111122223333-us-east-1-an/*"
    }]
  })

  tags = {
    Team = "claims-eng"
  }
}
