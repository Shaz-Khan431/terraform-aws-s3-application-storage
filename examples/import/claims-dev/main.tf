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

# Adopts an existing bucket that was created with the module's naming convention outside of
# Terraform. Only works if the name already matches <application>-<environment>-<purpose>-
# <account_id>-<region>-an. Buckets with other names need to be migrated instead (see
# docs/design.md). Review the plan before applying: the bucket policy and lifecycle configuration
# are replaced as whole documents, so anything in them the module doesn't define is removed.
module "storage" {
  # Consumers outside this repo pin a release tag:
  # source = "git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git?ref=application_storage/v0.1.0"
  source = "../../../application_storage"

  application         = "claims"
  environment         = "dev"
  purpose             = "remits"
  data_classification = "phi"

  kms_key_arn       = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  access_log_bucket = "pbm-dev-s3-access-logs"
}

# One import block per resource the module manages, each using the bucket name as its ID.
# The ID has to be written out in each block because Terraform 1.5 only accepts a plain string.
import {
  to = module.storage.aws_s3_bucket.this
  id = "claims-dev-remits-111122223333-us-east-1-an"
}

import {
  to = module.storage.aws_s3_bucket_ownership_controls.this
  id = "claims-dev-remits-111122223333-us-east-1-an"
}

import {
  to = module.storage.aws_s3_bucket_public_access_block.this
  id = "claims-dev-remits-111122223333-us-east-1-an"
}

import {
  to = module.storage.aws_s3_bucket_server_side_encryption_configuration.this
  id = "claims-dev-remits-111122223333-us-east-1-an"
}

import {
  to = module.storage.aws_s3_bucket_versioning.this
  id = "claims-dev-remits-111122223333-us-east-1-an"
}

import {
  to = module.storage.aws_s3_bucket_lifecycle_configuration.this
  id = "claims-dev-remits-111122223333-us-east-1-an"
}

# Only when access_log_bucket is set: the logging resource uses count, hence [0]
import {
  to = module.storage.aws_s3_bucket_logging.this[0]
  id = "claims-dev-remits-111122223333-us-east-1-an"
}

import {
  to = module.storage.aws_s3_bucket_policy.this
  id = "claims-dev-remits-111122223333-us-east-1-an"
}
