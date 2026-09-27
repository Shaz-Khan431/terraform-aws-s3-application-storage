# Account and region come from the caller's provider configuration rather than
# variables, so the bucket name always matches where the bucket is created.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Partition ("aws", "aws-us-gov", "aws-cn") so the bucket ARN can be built before the bucket exists
# Specifically to account for "plan only" verification
data "aws_partition" "current" {}
