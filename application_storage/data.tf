# Account and region come from the caller's provider configuration rather than
# variables, so the bucket name always matches where the bucket is created.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
