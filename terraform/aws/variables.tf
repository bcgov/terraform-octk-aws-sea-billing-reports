
variable "kms_master_key_alias" {
    type        = string
    description = "KMS Master Key Alias for encrypting objects in an S3 bucket."
}

variable "kms_master_key_id" {
    type        = string
    description = "KMS Master Key ID for ecnrypting files on EFS"
}

variable "athena_database" {
    type        = string
    description = "Name of Athena Database"
}

variable "athena_queries_bucket_arn" {
    type        = string
    description = "ARN of the S3 Bucket used by Athena Queries"
}

variable "billing_cur_bucket_arn" {
    type        = string
    description = "ARN of the Current S3 Bucket Accessed by Lambda"
}