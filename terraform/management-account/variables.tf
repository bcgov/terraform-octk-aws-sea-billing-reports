variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "ca-central-1"
}

# Supplied by env var: TF_VAR_operator_account_id
variable "ops_account_id" {
  description = "LZ Operator AWS Account ID"

  type    = string
  default = "111519536032"
}

# Supplied by env var: TF_VAR_master_account_phase1_bucket_suffix
variable "mgmt_account_phase1_bucket_suffix" {
  description = "Master account phase1 S3 bucket suffix"

  type    = string
  default = "1rzwj0x4t5b9l"
}