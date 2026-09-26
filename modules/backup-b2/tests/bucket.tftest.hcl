mock_provider "b2" {
  mock_data "b2_account_info" {
    defaults = {
      s3_api_url = "https://s3.eu-central-003.backblazeb2.com"
    }
  }

  mock_resource "b2_bucket" {
    defaults = {
      bucket_id = "4a48fe8875c6214145260818"
    }
  }

  mock_resource "b2_application_key" {
    defaults = {
      application_key_id = "0034a48fe8875c60000000001"
      application_key    = "K003mockedsecretvalue"
    }
  }
}

run "private_encrypted_bucket_with_a_key_for_it_only" {
  variables {
    bucket_name = "example-stack-backup"
  }

  assert {
    condition     = b2_bucket.this.bucket_type == "allPrivate"
    error_message = "The bucket is not private."
  }

  assert {
    condition     = b2_bucket.this.default_server_side_encryption[0].mode == "SSE-B2" && b2_bucket.this.default_server_side_encryption[0].algorithm == "AES256"
    error_message = "The bucket does not encrypt files by default."
  }

  assert {
    condition     = length(b2_bucket.this.lifecycle_rules) == 1 && b2_bucket.this.lifecycle_rules[0].file_name_prefix == ""
    error_message = "The lifecycle rule does not cover every file."
  }

  assert {
    condition     = b2_bucket.this.lifecycle_rules[0].days_from_hiding_to_deleting == 30
    error_message = "Deleted files are not kept for keep_deleted_days, by default 30."
  }

  assert {
    condition     = b2_bucket.this.lifecycle_rules[0].days_from_uploading_to_hiding == null
    error_message = "Live files are hidden after a while; restic data must stay until restic deletes it."
  }

  assert {
    condition     = b2_bucket.this.lifecycle_rules[0].days_from_starting_to_canceling_unfinished_large_files == 1
    error_message = "Unfinished large uploads are not cancelled."
  }

  assert {
    condition     = b2_application_key.restic.bucket_ids == toset([b2_bucket.this.bucket_id])
    error_message = "The key is not limited to this bucket."
  }

  assert {
    condition = b2_application_key.restic.capabilities == toset([
      "listAllBucketNames", "listBuckets", "readBuckets", "listFiles", "readFiles", "writeFiles", "deleteFiles",
    ])
    error_message = "The key has other capabilities than restic needs."
  }

  assert {
    condition     = b2_application_key.restic.key_name == "example-stack-backup"
    error_message = "The key is not named after the bucket by default."
  }

  assert {
    condition     = output.repository == "s3:https://s3.eu-central-003.backblazeb2.com/example-stack-backup"
    error_message = "The repository is not the S3 endpoint of the account followed by the bucket."
  }

  assert {
    condition     = output.access_key_id == b2_application_key.restic.application_key_id && output.secret_access_key == b2_application_key.restic.application_key
    error_message = "The outputs do not carry the key restic uses."
  }
}

run "key_name_and_retention_are_set" {
  variables {
    bucket_name       = "example-stack-backup"
    key_name          = "restic-vps"
    keep_deleted_days = 7
  }

  assert {
    condition     = b2_application_key.restic.key_name == "restic-vps"
    error_message = "key_name is ignored."
  }

  assert {
    condition     = b2_bucket.this.lifecycle_rules[0].days_from_hiding_to_deleting == 7
    error_message = "keep_deleted_days is ignored."
  }
}

run "bucket_names_outside_the_b2_rules_are_refused" {
  command = plan

  variables {
    bucket_name = "Stack_Backup"
  }

  expect_failures = [var.bucket_name]
}

run "reserved_prefix_is_refused" {
  command = plan

  variables {
    bucket_name = "b2-stack-backup"
  }

  expect_failures = [var.bucket_name]
}

run "bad_key_names_are_refused" {
  command = plan

  variables {
    bucket_name = "example-stack-backup"
    key_name    = "restic vps"
  }

  expect_failures = [var.key_name]
}

run "zero_retention_is_refused" {
  command = plan

  variables {
    bucket_name       = "example-stack-backup"
    keep_deleted_days = 0
  }

  expect_failures = [var.keep_deleted_days]
}
