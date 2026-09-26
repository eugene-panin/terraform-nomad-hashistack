variable "bucket_name" {
  description = "Name of the bucket. B2 bucket names are global across all accounts: 6 to 63 lowercase letters, digits and hyphens, not starting with b2-."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{4,61}[a-z0-9]$", var.bucket_name)) && !startswith(var.bucket_name, "b2-")
    error_message = "bucket_name must be 6 to 63 lowercase letters, digits and hyphens, start and end with a letter or digit, and not start with b2-."
  }
}

variable "key_name" {
  description = "Name of the application key restic uses. Null means the bucket name."
  type        = string
  default     = null

  validation {
    condition     = var.key_name == null || can(regex("^[A-Za-z0-9-]{1,100}$", coalesce(var.key_name, "x")))
    error_message = "key_name must be 1 to 100 letters, digits and hyphens."
  }
}

variable "keep_deleted_days" {
  description = "Days a file deleted by restic, or by anyone holding the key, stays recoverable in the bucket before B2 removes it."
  type        = number
  default     = 30

  validation {
    condition     = var.keep_deleted_days >= 1 && floor(var.keep_deleted_days) == var.keep_deleted_days
    error_message = "keep_deleted_days must be a whole number of at least 1."
  }
}
