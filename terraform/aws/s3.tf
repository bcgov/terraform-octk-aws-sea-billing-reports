
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "billing_reports" {
  bucket = "billing-reports-${data.aws_caller_identity.current.account_id}"
  acl    = "private"


  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = var.kms_master_key_alias
        sse_algorithm     = "aws:kms"
      }
    }
  }

  tags = local.common_tags
}
