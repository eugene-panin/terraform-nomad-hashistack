# backup-b2

A private Backblaze B2 bucket for restic backups, and an application key that
reaches only that bucket. The outputs are what restic needs: the repository
on the S3-compatible API of B2, and the key.

```hcl
module "backup" {
  source  = "eugene-panin/hashistack/nomad//modules/backup-b2"
  version = "~> 0.5"

  bucket_name = "example-stack-backup"
}
```

restic reads them from `RESTIC_REPOSITORY`, `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY`.

The provider needs a key of its own, made once by hand in the B2 web UI with
the right to create buckets and keys. Pass it as `B2_APPLICATION_KEY_ID` and
`B2_APPLICATION_KEY`. The key this module makes is narrower: listing, reading,
writing and deleting files in this bucket. Its secret is in the state, so
encrypt the state.

- **Files and uploads.** Files are encrypted at rest (SSE-B2). Unfinished
  large uploads are cancelled after a day.
- **Deleted files.** B2 keeps every version of a file. When restic removes
  data, B2 only hides it; after `keep_deleted_days` (30 by default) it deletes
  it for good. Until then a file deleted by mistake, or by someone holding the
  key, can be restored in the B2 web UI. After that it stops costing storage.
- **Destroying the bucket.** A bucket that holds backups cannot be destroyed:
  B2 refuses to delete a bucket that is not empty, and the provider does not
  empty it first.

## Tested

`tofu test` and `terraform test` with a mocked B2 provider check that:

- the bucket is private and encrypted by default;
- its only lifecycle rule covers every file, deletes hidden files after
  `keep_deleted_days` and never hides live ones;
- unfinished uploads are cancelled after a day;
- the key reaches this bucket only, with exactly the capabilities restic uses,
  and is named after the bucket unless `key_name` is set;
- the repository is the S3 endpoint of the account followed by the bucket, and
  the outputs carry the key;
- a bucket name outside the B2 rules, a `b2-` prefix, a bad key name and a
  retention under a day are refused.

Each check fails when its part of the module is changed.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9 |
| b2 | >= 0.14, < 1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| b2 | >= 0.14, < 1.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Name of the bucket. B2 bucket names are global across all accounts: 6 to 63 lowercase letters, digits and hyphens, not starting with b2-. | `string` | n/a | yes |
| keep\_deleted\_days | Days a file deleted by restic, or by anyone holding the key, stays recoverable in the bucket before B2 removes it. | `number` | `30` | no |
| key\_name | Name of the application key restic uses. Null means the bucket name. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| access\_key\_id | ID of the application key restic uses, for AWS\_ACCESS\_KEY\_ID. |
| bucket\_id | ID of the bucket. |
| repository | restic repository on the S3-compatible API of B2, for RESTIC\_REPOSITORY. |
| secret\_access\_key | Secret of the application key restic uses, for AWS\_SECRET\_ACCESS\_KEY. |
<!-- END_TF_DOCS -->
