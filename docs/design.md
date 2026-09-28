# Design notes: application_storage

Longer notes behind the [README](../README.md): why things are set up the way they are, how I
tested the module, and the plan output I checked against.

## How the module is consumed

This repo only has the module. Teams would call it from their own Terraform config repo, pinned to a
release tag, and that repo would handle deployment:

- A plan runs on every pull request and gets posted for review.
- After the PR is approved, the saved plan is applied (`terraform apply tfplan`). Terraform won't
  apply a saved plan if the state changed since it was created. Plan files can contain sensitive
  values, so they should be short-lived and access restricted.
- The apply job is gated with a GitHub Environment that needs a reviewer.
- State lives in an S3 backend with native locking (`use_lockfile = true`, Terraform 1.10+).
- An open PR for an environment locks it until the PR is merged or closed. Atlantis does this per
  directory or workspace. With plain GitHub Actions you'd need a concurrency group per environment
  and a lock check.
- GitHub Actions gets AWS access through an OIDC role instead of long-lived keys.

That's also why the examples don't have a backend. They show how to call the module, not how to
deploy it.

## Design decisions

### Naming

Buckets are named `<application>-<environment>-<purpose>-<account_id>-<region>-an`. `application`,
`environment` and `purpose` are required inputs. The account and region come from data sources, so
the name matches wherever the bucket is created. I made `purpose` required instead of giving it a
default so the name says what's in the bucket, and so two buckets for the same app and environment
can't end up with the same name. `environment` has to be `dev`, `qa`, `uat` or `prod`.

### Length limits

S3 bucket names can be at most 63 characters. Validation in Terraform 1.5 can only look at one
variable at a time, so I gave each part its own limit instead of checking the full name.
`application` and `purpose` can be 2 to 13 characters. With `prod`, a 12 digit account ID, one of the
longest region names and the `-an` suffix, the longest possible name comes out to exactly 63.

Characters are checked with `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`: lowercase letters, numbers and
hyphens, starting and ending with a letter or number. I left out dots because they break HTTPS for
virtual-hosted-style requests. I worked out the pattern on [regex101](https://regex101.com) using
the Golang flavor (Terraform uses Go's RE2 engine), and there's a test for each part of it.

### Tags

Each bucket gets `Application`, `Environment`, `Purpose`, `DataClassification`, `ManagedBy` and
`Module`. Caller tags are merged in first and the standard tags last, so if a caller passes one of
the same keys the module's value wins. `data_classification` (`phi`, `confidential` or `internal`)
is required so you can find all the PHI buckets with one tag query.

Org-wide tags like `CostCenter` and `Owner` should go in the caller's provider `default_tags`. That
way they're applied to everything a team deploys, not only buckets, and AWS Organizations tag
policies can enforce them. The module only sets tags it knows the values for.

### Inputs

The inputs are flat, and every optional one has a safe default, so the smallest module call is four
lines. For optional features the value itself turns the feature on: `access_log_bucket = null` means
no logging, and `kms_key_arn = null` means SSE-S3. That way there's no separate on/off flag that
could disagree with the value (logging on with no bucket to send it to).

### Versioning

Versioning is on by default. Turning it off sets the status to `Suspended` rather than `Disabled`.
S3 doesn't let a versioned bucket go back to `Disabled`, so `Suspended` is the only "off" value that
works for both new and existing buckets.

Old (noncurrent) versions expire after 90 days by default, and the rule stays even when versioning is
off. Suspending versioning doesn't delete the versions that are already there. My first version
removed the expiration rule when versioning was off, which would have kept those versions (and the
storage cost) forever. I caught that while testing.

Expired delete markers get cleaned up and incomplete multipart uploads are aborted after 7 days.
Neither is configurable since there's no reason to keep them.

### Access logging

Logging is optional and goes to an existing central log bucket instead of one the module creates.
If the module created the log bucket, the app team could delete its own audit logs. A log bucket also
needs different settings from an app bucket, and creating one per app bucket doubles the number of
buckets to manage.

Log files use the date-partitioned key format, partitioned by event time:
`s3-access-logs/<account_id>/<region>/<bucket>/YYYY/MM/DD/`. That lets a lot of buckets share one
log bucket and makes it easy to query by date. A precondition stops a bucket from logging to itself.

### Encryption

SSE-S3 is the default. Passing `kms_key_arn` switches to SSE-KMS with S3 Bucket Keys, which cut KMS
requests by up to 99%. The downside is that KMS's CloudTrail entries show the bucket rather than each
object. The module doesn't create keys, since key policies are usually owned by a security team and
one key often covers several buckets. The key has to be a full key ARN: an alias can be pointed at a
different key later, and a bare key ID doesn't work across accounts.

### Bucket policy

The module adds two Deny statements (see Security decisions). Callers can add their own with
`additional_policy_json`. Those get appended with `concat()`, so they can't replace the module's
statements, and in IAM an explicit Deny beats an Allow, so an added Allow can't weaken them.

I built the policy with `jsonencode()` instead of an `aws_iam_policy_document` data source. Mocked
providers return random values for data sources, so with the data source I couldn't have tested the
policy at plan time.

### No force_destroy input

`force_destroy` is set to `false` in the code. Bucket names come from the inputs and S3 names can't
be changed, so renaming `purpose` makes Terraform replace the bucket. With `force_destroy` on, that
one-word change would delete everything in the bucket. Emptying a bucket should be done on purpose,
by hand.

### Outputs

`bucket_name` and `bucket_arn` are built from `aws_s3_bucket.this.bucket`, which is set in the
config. That means they're known at plan time, and since they reference the resource, anything a
consumer builds from them waits until the bucket exists. I didn't output values the caller passed in
(`kms_key_arn`, `access_log_bucket`) since they already have them.

### Versions

Terraform `>= 1.5.0`, because 1.5.x was the last MPL-licensed release and some teams stayed on it.
AWS provider `>= 6.37`, which added `bucket_namespace`. I only set minimums, following HashiCorp's
guidance for shared modules. Each consumer's lock file pins the exact versions.

### Examples

There are two apps in two environments, and each one is set up differently for a reason:

- `claims/dev` keeps old versions for 30 days
- `claims/qa` gives a reporting role in another account read access
- `formulary/dev` turns versioning off since the exports get regenerated
- `formulary/qa` turns on access logging

Each example is a provider block and a module call. In `claims/qa` the policy writes out the bucket
ARN from the naming convention. Using `module.storage.bucket_arn` inside the same module's input would
be a circular reference.

## Security decisions

### Account regional namespace

The bucket names follow a predictable pattern. In S3's global namespace that would make them easy to
squat, where someone creates the name first and apps or partners set up for it upload to their
bucket, or to snipe, where someone re-creates a deleted name that old configs still point to. In
2025, watchTowr re-registered about 150 abandoned bucket names and got over 8 million requests from
systems still using them.

The `-<account_id>-<region>-an` suffix together with `bucket_namespace = "account-regional"` makes
S3 check that the account and region in the name match the account creating the bucket. So only this
account can own these names, including after a bucket is deleted.

### TLS

The bucket policy denies any request that isn't using TLS (`aws:SecureTransport = false`) or is using
TLS older than 1.2 (`s3:TlsVersion`), for all principals.

### SSE-C blocked

`blocked_encryption_types = ["SSE-C"]`. SSE-C lets whoever uploads an object encrypt it with a key
S3 doesn't keep. In January 2025 the Codefinger campaign used stolen credentials to re-encrypt
people's objects with SSE-C and then asked for payment for the keys.

### No public access

All four Block Public Access settings are on for the bucket, on top of any account-level setting.
ACLs are disabled with `BucketOwnerEnforced`, so the account owns every object, including ones
uploaded by partners, and access comes only from IAM and the bucket policy. Block Public Access also
rejects any caller policy statement that would make the bucket public.

### Setting defaults explicitly

AWS now blocks public access, disables ACLs and blocks SSE-C on new buckets by default, and the
provider defaults `force_destroy` to `false`. I set all of these in the code anyway so they're visible
in review, covered by tests, and put back by Terraform if someone changes them in the console.

### Checkov skips

Two Checkov checks are skipped in the code, with the reason next to each: cross-region replication,
which is a disaster recovery decision for each app, and event notifications, which depend on how each
consumer is built.

## Validation and testing

None of this needs `terraform apply` or creates anything in AWS.

### Basic checks

```bash
terraform fmt -check -recursive

cd application_storage
terraform init -backend=false
terraform validate

cd ../examples/claims/dev          # any example
terraform init -backend=false
terraform validate
terraform plan                     # needs read-only AWS credentials, creates nothing
```

### Terraform tests

```bash
cd application_storage
terraform init -backend=false
terraform test
```

There are 37 plan-only tests using a mocked AWS provider, so they don't need credentials. None of the
tests use `override_during`. That keeps values AWS only fills in on create unknown during the plan,
the same as a real first plan. If the policy, bucket name or ARN depended on one of those values, the
tests couldn't evaluate them and would fail with `Unknown condition value`. Adding
`override_during = plan` would make the mocks fill those values in, and the tests would pass on
values that wouldn't be known in a real plan. I checked this by switching the policy to use
`aws_s3_bucket.this.arn`, and the policy test failed.

I also broke the module on purpose to make sure the tests catch it. Turning off a public access
setting, lowering the TLS minimum, changing a Deny to an Allow and pointing the `tags` output at
`var.tags` each made the matching test fail.

| Behavior | Test |
| --- | --- |
| Name follows the convention, in the account regional namespace | `naming`: `bucket_name_follows_convention` |
| Longest possible name fits in 63 characters | `naming`: `longest_name_fits_s3_limit` |
| Standard tags win over caller tags, other caller tags kept | `naming`: `standard_tags_override_caller_tags` |
| Invalid application, purpose, environment or classification rejected | `naming`: `rejects_*` (10 tests) |
| Public access blocked, ACLs disabled, `force_destroy` off | `security`: `public_access_fully_blocked`, `acls_disabled`, `force_destroy_off` |
| SSE-S3 by default, SSE-KMS with Bucket Keys when a key is given | `security`: `sse_s3_by_default`, `sse_kms_when_key_given` |
| SSE-C blocked | `security`: `sse_c_blocked` |
| TLS enforced (Deny for all principals, conditions, bucket and objects) | `security`: `policy_enforces_tls` |
| Caller statements added after the module's statements | `security`: `caller_statements_appended_after_baseline` |
| ARN uses the current partition (GovCloud) | `security`: `govcloud_partition_in_policy` |
| KMS alias or key ID and malformed policy JSON rejected | `security`: `rejects_*` (4 tests) |
| Versioning on, old versions expire after 90 days, delete markers cleaned up | `versioning`: `versioning_enabled_by_default`, `noncurrent_versions_expire_after_90_days` |
| Incomplete uploads aborted after 7 days | `versioning`: `incomplete_uploads_aborted_after_7_days` |
| Custom retention used | `versioning`: `custom_noncurrent_expiration` |
| Versioning off gives Suspended, and old versions still expire | `versioning`: `versioning_off_suspends_and_still_expires` |
| Zero or fractional retention rejected | `versioning`: `rejects_*` (2 tests) |
| Logging off by default, on with partitioned keys | `logging`: `bucket_logging_off_by_default`, `bucket_logging_on_with_partitioned_keys` |
| Bucket can't log to itself | `logging`: `rejects_logging_to_itself` |
| Outputs correct and known at plan, tags output matches the bucket | `outputs`: `default_outputs` |

### Static analysis

```bash
tflint --init && tflint --chdir=application_storage --config "$PWD/.tflint.hcl"
checkov -d application_storage --framework terraform
terraform-docs -c .terraform-docs.yml --output-check application_storage
```

### CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs all of this on every pull request and
push to `main`: fmt, validate on the module and every example (with the latest Terraform and with
1.5.7, the minimum the module supports), the tests, TFLint (all Terraform rules and the AWS ruleset),
Checkov, and a check that the generated tables in the module README are up to date. `main` has a
ruleset that requires a pull request and passing checks.

### Plan against a real account

I ran `terraform plan` on `examples/claims/dev` against an AWS account (read-only, no state written).
It planned 8 resources. The bucket policy was fully visible before apply, and the provider's
`default_tags` were merged with the module's tags. The account ID below is replaced with a placeholder.

```
+ bucket           = "claims-dev-remits-111122223333-us-east-1-an"
+ bucket_namespace = "account-regional"
+ tags_all         = {
    + "Application"        = "claims"
    + "CostCenter"         = "cc-1042"
    + "DataClassification" = "phi"
    + "Environment"        = "dev"
    + "ManagedBy"          = "terraform"
    + "Module"             = "application_storage"
    + "Owner"              = "claims-platform"
    + "Purpose"            = "remits"
    + "Team"               = "claims-eng"
  }

+ policy = jsonencode({
    + Statement = [
        + { Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*",
            Condition = { Bool = { "aws:SecureTransport" = "false" } },
            Resource  = ["arn:aws:s3:::claims-dev-remits-111122223333-us-east-1-an", ".../*"] },
        + { Sid = "DenyOutdatedTLS", Effect = "Deny", Principal = "*", Action = "s3:*",
            Condition = { NumericLessThan = { "s3:TlsVersion" = "1.2" } }, ... },
      ]
  })

Plan: 8 to add, 0 to change, 0 to destroy.
```

The mocked tests can't show `tags_all`, because the real provider does the `default_tags` merge. This
plan is how I checked it.

## Assumptions

- One bucket per module call. Teams that need more call the module again with a different `purpose`.
- The access log bucket already exists in the same account and region, uses SSE-S3 (server access
  logs can't be delivered to an SSE-KMS bucket), and has a policy that lets
  `logging.s3.amazonaws.com` write to it. The ACL-based setup won't work because ACLs are disabled.
- KMS keys already exist and their key policies are managed somewhere else. Anything reading or
  writing objects needs `kms:GenerateDataKey` and `kms:Decrypt` on the key.
- The caller configures the AWS provider (region, credentials and org-wide `default_tags`).
- A security team has CloudTrail S3 data events set up org-wide. Server access logs are best-effort
  and are there in addition to that.
- The environment list (`dev`, `qa`, `uat`, `prod`) and classification list (`phi`,
  `confidential`, `internal`) match the org's conventions.

## Tradeoffs

- Fixed naming keeps names predictable, but the module can't take over existing buckets that are
  named differently. That would need a `bucket_name` override, which would also let people skip the
  convention.
- The account regional suffix takes about 31 of the 63 characters, so `application` and `purpose` are
  limited to 13 characters each.
- Reserved S3 prefixes (`xn--`, `sthree-`, `amzn-s3-demo-`) aren't validated. They're rare, and S3
  rejects them at apply.
- `access_log_bucket` isn't checked, so a wrong name fails at apply instead of plan. Checking it at
  plan with a data source would mean the deploy role needs read access to the security team's log
  bucket.
- I went with flat versioning inputs over a grouped object because they're easier to read. The
  object would make the connection between them clearer, but it matters less now that expiration
  always applies.
- There's no option to keep old versions forever. Teams that need a long history can set a large
  number of days. Keeping everything indefinitely is usually a cost and compliance problem for PHI.
- Callers who add policy statements have to write out the bucket ARN from the naming convention,
  since the module's own output can't be used in its input.
- Bucket Keys give up per-object KMS CloudTrail entries in exchange for up to 99% fewer KMS requests.
- With minimum-only version constraints, a future major provider version could break consumers when
  they upgrade. Their lock files and upgrade process should catch that.

## Releasing

[terraform-module-releaser](https://github.com/techpivot/terraform-module-releaser) creates releases
when pull requests are merged. Each PR gets a comment showing what would be released. Merging creates
a tag (`application_storage/vX.Y.Z`), a GitHub release and wiki pages generated with terraform-docs.

The version bump comes from the Conventional Commit messages in the PR: `fix:`, `chore:` and `docs:`
are patches, `feat:` is a minor bump, and `feat!:` or a `BREAKING CHANGE:` footer is a major bump. The
first release is `v0.1.0`. Changes to only `examples/`, tests or markdown don't create a new version.

The module is in `application_storage/` instead of the repo root because the releaser only finds
modules in subdirectories.

Each release tag points to a separate commit the releaser creates with only the module's `.tf` files,
at the root. So the source address has no subdirectory:
`git::https://github.com/Shaz-Khan431/terraform-aws-s3-application-storage.git?ref=application_storage/v0.1.0`.
I first documented it with `//application_storage` and found the mistake by running `terraform init`
against the published tag.

## With more time

- Use `data_classification` to require a KMS key and access logging for `phi` buckets. This needs
  cross-variable validation (Terraform 1.9+) or a precondition.
- Object Lock for records with legal retention requirements. I left it out because compliance mode
  can't be undone, it overrides lifecycle expiration, and the retention period is a legal decision.
- Optional replication for disaster recovery.
- Keep the newest few old versions (`newer_noncurrent_versions`) so objects that rarely change still
  have some history.
- Move old versions to cheaper storage classes (Standard-IA, Glacier) before they expire.
- Fill in the bucket ARN for caller policy statements so callers don't have to repeat the naming
  convention.
- Pin GitHub Actions to commit SHAs and use Dependabot to update them. Tags can be moved, which is
  what happened in the 2025 tj-actions/changed-files compromise.
- Manage the branch ruleset in code (the GitHub provider's `github_repository_ruleset`).
- Nightly apply tests in a sandbox account to cover what mocks can't, like provider defaults and real
  API validation.

MFA Delete is out of scope. Only the root user can turn it on, so it can't be managed from a normal
pipeline.

## References

AWS

- [General purpose bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html)
- [Namespaces for general purpose buckets](https://docs.aws.amazon.com/AmazonS3/latest/userguide/gpbucketnamespaces.html)
- [Default encryption FAQ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-encryption-faq.html)
- [SSE-C default setting FAQ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-s3-c-encryption-setting-faq.html)
- [S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html)
- [Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)
- [Object Ownership and disabling ACLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)
- [Security best practices for S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [Server access logging](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ServerLogs.html)
- [Lifecycle management](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [S3 ARN format](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-arn-format.html)
- [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [IAM policy elements](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html)
- [Tag policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html)

Terraform

- [AWS provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs), including [`aws_s3_bucket`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) and [`aws_s3_bucket_server_side_encryption_configuration`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration)
- [AWS provider changelog](https://github.com/hashicorp/terraform-provider-aws/blob/main/CHANGELOG.md) (6.37.0 added `bucket_namespace`)
- [Version constraints](https://developer.hashicorp.com/terraform/language/expressions/version-constraints)
- [Providers within modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers)
- [Tests](https://developer.hashicorp.com/terraform/language/tests) and [mocks](https://developer.hashicorp.com/terraform/language/tests/mocking)
- [HashiCorp license FAQ](https://www.hashicorp.com/license-faq)

Tools

- [terraform-module-releaser](https://github.com/techpivot/terraform-module-releaser)
- [TFLint](https://github.com/terraform-linters/tflint) and the [AWS ruleset](https://github.com/terraform-linters/tflint-ruleset-aws)
- [Checkov](https://www.checkov.io)
- [terraform-docs](https://terraform-docs.io)
- [regex101](https://regex101.com)

Incidents mentioned

- [Halcyon: ransomware encrypting S3 buckets with SSE-C (Codefinger)](https://www.halcyon.ai/blog/abusing-aws-native-services-ransomware-encrypting-s3-buckets-with-sse-c)
- [watchTowr: 8 million requests to abandoned S3 buckets](https://labs.watchtowr.com/8-million-requests-later-we-made-the-solarwinds-supply-chain-attack-look-amateur/)
- [CISA: tj-actions/changed-files compromise (CVE-2025-30066)](https://www.cisa.gov/news-events/alerts/2025/03/18/supply-chain-compromise-third-party-tj-actionschanged-files-cve-2025-30066-and-reviewdogaction)
