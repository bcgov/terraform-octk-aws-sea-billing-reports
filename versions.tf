terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.0"
      configuration_aliases = [
        aws.master-account,
        aws.Operations-account
      ]
    }
  }
}
