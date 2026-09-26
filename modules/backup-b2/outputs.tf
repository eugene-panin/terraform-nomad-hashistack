output "repository" {
  description = "restic repository on the S3-compatible API of B2, for RESTIC_REPOSITORY."
  value       = "s3:${data.b2_account_info.this.s3_api_url}/${b2_bucket.this.bucket_name}"
}

output "access_key_id" {
  description = "ID of the application key restic uses, for AWS_ACCESS_KEY_ID."
  value       = b2_application_key.restic.application_key_id
}

output "secret_access_key" {
  description = "Secret of the application key restic uses, for AWS_SECRET_ACCESS_KEY."
  value       = b2_application_key.restic.application_key
  sensitive   = true
}

output "bucket_id" {
  description = "ID of the bucket."
  value       = b2_bucket.this.bucket_id
}
