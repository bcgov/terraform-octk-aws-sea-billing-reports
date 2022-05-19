variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "ca-central-1"
}

variable "operator_account_id" {
  description = "ECF Operator AWS Account ID"

  type    = string
  default = ""
}

variable "master_account_phase1_bucket_suffix" {
  description = "Master account phase1 S3 bucket suffix"

  type    = string
  default = ""
}