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
