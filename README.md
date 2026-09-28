# terraform-aws-s3-application-storage

Terraform module (`application_storage`) for creating private S3 buckets for application data.
Encryption, TLS, public access blocking, versioning and tagging are set up by the module, and teams
only fill in what's specific to their app.

The examples are based on a pharmacy benefit manager: `claims` buckets hold PHI and `formulary`
buckets hold internal data.

More detail on the design, the test matrix and validation output is in
[docs/design.md](docs/design.md). Inputs and outputs are listed in the
[module README](application_storage/README.md).

```
application_storage/        the module
  tests/                    plan-only terraform tests (mocked AWS provider)
examples/                   claims/{dev,qa}, formulary/{dev,qa}, import/claims-dev
docs/design.md              design notes, test matrix, plan output
.github/workflows/          CI and release automation
```

## Usage

```hcl
module "storage" {
  source = "git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git?ref=application_storage/v0.1.0"

  application         = "claims"
  environment         = "dev"
  purpose             = "remits"
  data_classification = "phi"
}
```

This creates `claims-dev-remits-<account_id>-<region>-an`.

In practice teams would call this from their own Terraform config repo, pinned to a release tag.
That repo handles state, runs plans on PRs and applies after approval.

## Design decisions

Bucket names follow `<application>-<environment>-<purpose>-<account_id>-<region>-an`. The account
and region are looked up with data sources instead of being passed in. The name inputs are validated
so the bucket name is valid and stays under S3's 63 character limit.

Six tags are added to every bucket: `Application`, `Environment`, `Purpose`, `DataClassification`,
`ManagedBy` and `Module`. Callers can add their own tags but can't override these. I made
`data_classification` required so PHI buckets can be found by tag. Org-wide tags like `CostCenter`
belong in the caller's provider `default_tags`.

Four inputs are required and the rest have safe defaults. Optional features are enabled by passing a
value, like a log bucket name or a KMS key ARN, instead of a separate on/off flag.

Versioning is on by default. Turning it off sets it to `Suspended`, because S3 doesn't allow going
back to `Disabled`. Old versions expire after 90 days, and that rule stays in place when versioning is
off since suspending doesn't remove the versions that already exist.

Access logs go to an existing central log bucket rather than one the module creates, so app teams
can't delete their own logs. Log keys are partitioned by date, and the module won't let a bucket log
to itself.

Encryption uses SSE-S3 unless a KMS key ARN is passed, in which case it uses SSE-KMS with Bucket Keys.
The module doesn't create keys.

Callers can add bucket policy statements. They get added after the module's TLS statements and can't
replace them.

There's no `force_destroy` option. Since the name comes from the inputs, renaming `purpose` replaces
the bucket, and I didn't want that to be able to delete data.

The bucket ARN is built from the name so the full bucket policy shows up in the first plan, before
anything is applied.

## Security decisions

- Buckets are created in the account regional namespace, so no other AWS account can claim these
  names, before or after a bucket is deleted.
- The bucket policy denies requests that don't use TLS, or use TLS older than 1.2.
- Block Public Access is fully on and ACLs are disabled (`BucketOwnerEnforced`).
- SSE-C is blocked. It was used in the 2025 Codefinger ransomware campaign to re-encrypt objects with
  the attacker's key.
- Some of these are AWS defaults now, but I set them explicitly so they show up in review, get tested
  and get corrected if someone changes them.

## Validation

None of this needs `terraform apply` or creates anything.

```bash
terraform fmt -check -recursive

cd application_storage
terraform init -backend=false
terraform validate
terraform test          # 37 plan-only tests, mocked provider, no credentials

cd ../examples/claims/dev
terraform init -backend=false
terraform validate
terraform plan          # needs read-only AWS credentials
```

CI runs the same checks on every PR, along with TFLint, Checkov, a terraform-docs check and a
`validate` run on Terraform 1.5.7 (the minimum version the module supports). The
[test matrix](docs/design.md#validation-and-testing) lists what each test covers.

## Assumptions

- The central log bucket and any KMS keys already exist.
- The caller configures the AWS provider (region, credentials, org-wide tags).
- CloudTrail data events are set up at the org level for audit.
- One bucket per module call.

## Tradeoffs

- Fixed naming limits `application` and `purpose` to 13 characters. Existing buckets can only be
  imported if their name already matches the convention. Others need to be migrated to a new bucket,
  covered in [docs/design.md](docs/design.md#import-and-migration).
- A wrong `access_log_bucket` name fails at apply instead of plan. Checking it at plan would mean
  giving the deploy role read access to the security team's log bucket.
- Callers adding policy statements have to write out the bucket ARN from the naming convention.
- Bucket Keys cut KMS costs but KMS audit logs show the bucket instead of each object.

## With more time

- Require KMS and access logging for `phi` buckets (needs Terraform 1.9 for cross-variable validation)
- Optional Object Lock, replication and storage class transitions
- Fill in the bucket ARN for caller policy statements automatically
- Pin GitHub Actions to commit SHAs and manage the branch ruleset in code
- Apply tests in a sandbox account on PRs that change the module (create, check, destroy), plus a
  monthly run against the latest AWS provider, since only minimum versions are pinned

## Releasing

Merged PRs are released with
[terraform-module-releaser](https://github.com/techpivot/terraform-module-releaser) as
`application_storage/vX.Y.Z`, with the version bump based on Conventional Commit messages. `main`
requires a PR and passing CI.
