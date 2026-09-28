provider "aws" {
  region = "us-east-1"

  # Organization-wide tags belong here, not in the module's tags input
  default_tags {
    tags = {
      CostCenter = "cc-2210"
      Owner      = "formulary-platform"
    }
  }
}

# Module defaults plus access logging, which QA enables to audit test runs
module "storage" {
  # Consumers outside this repo pin a release tag:
  # source = "git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git//application_storage?ref=application_storage/v0.1.0"
  source = "../../../application_storage"

  application         = "formulary"
  environment         = "qa"
  purpose             = "exports"
  data_classification = "internal"

  access_log_bucket = "pbm-qa-s3-access-logs"
}
