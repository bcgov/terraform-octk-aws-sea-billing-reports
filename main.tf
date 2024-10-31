module "management-account" {
  source                            = "./terraform/management-account"
  ops_account_id                    = var.ops_account_id

  providers = {
    aws = aws.Management-account
  }
}

module "operations-account" {
  source             = "./terraform/operations-account"
  lz_mgmt_account_id = var.mgmt_account_id
  lambda_arn = var.lambda_arn
  lambda_function_name= var.lambda_function_name

  providers = {
    aws = aws.Operations-account
  }

  depends_on = [module.management-account]
}
