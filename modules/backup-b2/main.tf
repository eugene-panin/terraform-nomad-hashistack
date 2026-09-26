data "b2_account_info" "this" {}

resource "b2_bucket" "this" {
  bucket_name = var.bucket_name
  bucket_type = "allPrivate"

  default_server_side_encryption {
    mode      = "SSE-B2"
    algorithm = "AES256"
  }

  lifecycle_rules {
    file_name_prefix                                       = ""
    days_from_hiding_to_deleting                           = var.keep_deleted_days
    days_from_starting_to_canceling_unfinished_large_files = 1
  }
}

resource "b2_application_key" "restic" {
  key_name   = coalesce(var.key_name, var.bucket_name)
  bucket_ids = [b2_bucket.this.bucket_id]
  capabilities = [
    "listAllBucketNames",
    "listBuckets",
    "readBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
    "deleteFiles",
  ]
}
