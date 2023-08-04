module "management-account" {
  source                            = "./management-account"
  ops_account_id                    = var.ops_account_id
  mgmt_account_phase1_bucket_suffix = var.mgmt_account_phase1_bucket_suffix

  providers = {
    aws = aws.master-account
  }
}

module "operations-account" {
  source             = "./operations-account"
  lz_mgmt_account_id = var.mgmt_account_id

  providers = {
    aws = aws.Operations-account
  }

  depends_on = [module.management-account]
}
