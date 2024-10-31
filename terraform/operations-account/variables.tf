variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "ca-central-1"
}

# Supplied by env var: TF_VAR_lz_master_account_id
variable "lz_mgmt_account_id" {
  description = "AWS Account ID for LZ Master account"

  type = string
}

variable "lambda_arn" {
  description = "ARN of the Lambda function"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
}

