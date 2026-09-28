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

# Claims remittance files contain PHI: customer managed KMS key and access logging.
# Dev churns through test files, so old versions are kept for 30 days instead of 90.
module "storage" {
  # Consumers outside this repo pin a release tag:
  # source = "git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git//application_storage?ref=application_storage/v0.1.0"
  source = "../../../application_storage"

  application         = "claims"
  environment         = "dev"
  purpose             = "remits"
  data_classification = "phi"

  kms_key_arn                        = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  access_log_bucket                  = "pbm-dev-s3-access-logs"
  noncurrent_version_expiration_days = 30

  tags = {
    Team = "claims-eng"
  }
}
