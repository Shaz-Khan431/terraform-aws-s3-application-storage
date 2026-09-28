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

# Formulary exports are internal, non-PHI data regenerated on every run, so dev skips
# versioning. Everything else uses the module defaults.
module "storage" {
  # Consumers outside this repo pin a release tag:
  # source = "git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git//application_storage?ref=application_storage/v0.1.0"
  source = "../../../application_storage"

  application         = "formulary"
  environment         = "dev"
  purpose             = "exports"
  data_classification = "internal"

  versioning_enabled = false
}
