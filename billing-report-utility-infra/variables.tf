variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "ca-central-1"
}


variable "lz_master_account_id" {
  description = "AWS Account ID for LZ Master account"

  type    = string
  default = ""
}