# application_storage

Creates a private S3 bucket for application data with secure defaults: encryption at rest,
TLS enforced in transit, public access blocked, versioning with expiration of old versions,
and consistent naming and tagging. Callers choose what differs between applications; the
security baseline can't be turned off.

## Usage

```hcl
module "storage" {
  source = "git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git?ref=application_storage/v0.1.0"

  application         = "claims"
  environment         = "dev"
  purpose             = "remits"
  data_classification = "phi"

  kms_key_arn       = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  access_log_bucket = "pbm-dev-s3-access-logs"
}
```

This creates `claims-dev-remits-<account_id>-<region>-an`. More complete examples are in
[`examples/`](../examples).

The module doesn't configure the AWS provider. Region, credentials and organization-wide tags
(e.g. `CostCenter`, `Owner` through `default_tags`) come from the caller's provider block.

## What you get

| Control | Default | Configurable |
| --- | --- | --- |
| Bucket name | `<application>-<environment>-<purpose>-<account_id>-<region>-an` in the account regional namespace | Through the naming inputs |
| Public access | All four Block Public Access settings on; ACLs disabled | No |
| Encryption at rest | SSE-S3; SSE-C uploads blocked | `kms_key_arn` switches to SSE-KMS with S3 Bucket Keys |
| Encryption in transit | Bucket policy denies non-TLS requests and TLS below 1.2 | No |
| Versioning | Enabled | `versioning_enabled` (off means Suspended) |
| Old versions | Expire after 90 days; expired delete markers removed | `noncurrent_version_expiration_days` |
| Incomplete multipart uploads | Aborted after 7 days | No |
| Access logging | Off | `access_log_bucket` |
| Bucket policy | TLS statements only | `additional_policy_json` statements are added after them |
| Deletion | A bucket that holds data can't be deleted by Terraform | No |

## Tags

Every bucket gets `Application`, `Environment`, `Purpose`, `DataClassification`,
`ManagedBy = "terraform"` and `Module = "application_storage"`. Tags passed in `tags` are
added, but can't override these six.

## Requirements for optional inputs

- **`access_log_bucket`** must already exist in the same account and region, use SSE-S3, and
  have a bucket policy allowing `logging.s3.amazonaws.com` to write to it.
- **`kms_key_arn`** must be a full key ARN, not an alias or key ID. Anything reading or writing
  objects needs `kms:GenerateDataKey` and `kms:Decrypt` on that key.
- **`additional_policy_json`** statements that reference the bucket should build its ARN from
  the naming convention (`arn:aws:s3:::<bucket name>`). Using this module's `bucket_arn`
  output inside its own input would be a circular reference.

## Testing

```bash
terraform init -backend=false
terraform test
```

Plan-only tests against a mocked AWS provider: no credentials needed and nothing is created.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.5.0 |
| aws | >= 6.37 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.37 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| application | Name of the application that owns the bucket, like claims. First segment of the bucket name. | `string` | n/a | yes |
| data\_classification | Sensitivity of the data in the bucket. Only options are phi, confidential, or internal. | `string` | n/a | yes |
| environment | Environment the bucket belongs to. Only options are dev / qa / uat / prod. | `string` | n/a | yes |
| purpose | What the bucket holds, like exports. Lets one application own several buckets per environment. | `string` | n/a | yes |
| access\_log\_bucket | Name of an existing bucket to receive S3 server access logs. Must be in the same account and region, use SSE-S3 encryption, and allow the S3 logging service to write to it. Null disables access logging. | `string` | `null` | no |
| additional\_policy\_json | Bucket policy JSON document whose statements are added after the module's baseline statements, e.g. built with jsonencode(). Statement must be a list. | `string` | `null` | no |
| kms\_key\_arn | ARN of an existing customer managed KMS key for default encryption. Null uses SSE-S3 (AES256). Callers writing or reading objects need kms:GenerateDataKey and kms:Decrypt on the key. | `string` | `null` | no |
| noncurrent\_version\_expiration\_days | Days to keep a previous object version before it is permanently deleted. Also applies after versioning is turned off, so versions kept from before still expire. | `number` | `90` | no |
| tags | Additional tags for the bucket. The module's standard tags (Application, Environment, Purpose, DataClassification, ManagedBy, Module) take precedence on conflicting keys. | `map(string)` | `{}` | no |
| versioning\_enabled | Keep previous versions of objects when they are overwritten or deleted. Setting this to false on a bucket that was already versioned suspends versioning; S3 keeps existing versions until they expire. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the bucket, for IAM policies granting access. Known at plan time. |
| bucket\_name | Name of the bucket, for application configuration and SDK/CLI calls. |
| bucket\_regional\_domain\_name | Regional domain name of the bucket. Can be used for things like CloudFront origins or region-specific endpoints. |
| encryption\_algorithm | Default encryption applied to objects: AES256 (SSE-S3) or aws:kms (SSE-KMS). With aws:kms, callers also need kms:GenerateDataKey and kms:Decrypt on the key. |
| tags | Tags applied to the bucket, including the module's standard tags. |
| versioning\_status | Versioning state of the bucket: Enabled or Suspended. |
<!-- END_TF_DOCS -->
