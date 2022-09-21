terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.70.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  app_name = "BCGov"
}

resource "aws_kms_key" "octk_aws_sea_billing_reports_kms_key" {
  description             = "CMK key for resources related to ${local.app_name} billing report utility"
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid : "Enable IAM User Permissions",
        Effect : "Allow",
        Principal : {
          AWS : data.aws_caller_identity.current.account_id
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "AllowUseOfTheKey",
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*",
        Effect   = "Allow",
        Principal = {
          AWS = [
            aws_iam_role.athena_cost_and_usage_report.arn
          ]
        }
      }
    ]
  })
}

resource "aws_kms_alias" "octk_aws_sea_billing_reports_kms_alias" {
  name          = "alias/${local.app_name}-BillingReports"
  target_key_id = aws_kms_key.octk_aws_sea_billing_reports_kms_key.key_id
}

resource "aws_s3_bucket" "athena_query_output_bucket" {
  bucket        = "bcgov-ecf-billing-reports-output-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = false
  acl           = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.octk_aws_sea_billing_reports_kms_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# Role needed to query account in the org. Resides on the master account
#
resource "aws_iam_role" "query_org_accounts" {
  name = "${local.app_name}-Query-Org-Accounts"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = [
            "organizations.amazonaws.com"
          ]
        },
      },
      {
        Effect = "Allow",
        Action = "sts:AssumeRole"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.ops_account_id}:root", // Change to line below after deployment to LZ0 Operations account
          ]
        }
      }
    ]
  })
}

# Attached AWS managed AWSOrganizationsReadOnlyAccess policy to the Query Org Accounts Role
resource "aws_iam_role_policy_attachment" "query_org_accounts_access" {
  role       = aws_iam_role.query_org_accounts.name
  policy_arn = "arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess"
}

# Role needed for Glue Crawler
# Grant Operations account access to assume role via STS
resource "aws_iam_role" "athena_cost_and_usage_report" {
  name = "${local.app_name}-Athena-Cost-and-Usage-Report"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = [
            "glue.amazonaws.com"
          ]
        },
      },
      {
        Effect = "Allow",
        Action = "sts:AssumeRole"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.ops_account_id}:root", // Maybe change to line below after deployment to LZ Operations account
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "athena_cost_and_usage_report_policies" {
  name = "AWSCURCrawlerComponentFunction"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*",
        Effect   = "Allow"
      },
      {
        Action = [
          "glue:UpdateDatabase",
          "glue:UpdatePartition",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:ImportCatalogToGlue"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
      {
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = "arn:aws:s3:::pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report*"
        Effect   = "Allow"
      },
      {
        Sid = "AthenaQueryOutputBucketPolicy"
        Action = [
          "s3:GetObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
          "s3:CreateBucket",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ],
        Resource = [
          aws_s3_bucket.athena_query_output_bucket.arn,
          "${aws_s3_bucket.athena_query_output_bucket.arn}/*",
        ]
        Effect = "Allow"
      },
      {
        Sid = "AllowTheUseOfCMKonOperationsAccount"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = [
          aws_kms_alias.octk_aws_sea_billing_reports_kms_alias.arn
        ]
        Effect = "Allow"
      }
    ]
  })
}

# Attach the AWSCURCrawlerComponentFunction IAM policy to Glue Crawler Role
resource "aws_iam_role_policy_attachment" "athena_cost_and_usage_report_access" {
  role       = aws_iam_role.athena_cost_and_usage_report.name
  policy_arn = aws_iam_policy.athena_cost_and_usage_report_policies.arn
}

# Attached AWS managed AWSGlueServiceRole policy to the Glue Crawler Role
resource "aws_iam_role_policy_attachment" "athena_cost_and_usage_report_glue_service_access" {
  role       = aws_iam_role.athena_cost_and_usage_report.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}


# Create Glue Database
resource "aws_glue_catalog_database" "athenacurcfn_cost_and_usage_report_database" {
  name = "cost_and_usage_report_athena_db"
}


resource "aws_glue_crawler" "aws_cur_crawler_cost_and_usage_report" {
  name          = "Cost-and-Usage-Report-Crawler"
  role          = aws_iam_role.athena_cost_and_usage_report.arn
  database_name = aws_glue_catalog_database.athenacurcfn_cost_and_usage_report_database.name
  description   = "A recurring crawler that keeps your CUR table in Athena up-to-date."
  schedule      = "cron(0 0 1 * ? *)" // Run crawler first day of each month at 00:00:00 UTC

  s3_target {
    path = "s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/"
    exclusions = [
      "**.json",
      "**.yml",
      "**.sql",
      "**.csv",
      "**.gz",
      "**.zip"
    ]
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "DELETE_FROM_DATABASE"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  lineage_configuration {
    crawler_lineage_settings = "DISABLE"
  }
}

resource "aws_glue_catalog_table" "cost_and_usage_report" {
  database_name = aws_glue_catalog_database.athenacurcfn_cost_and_usage_report_database.name
  name          = "cost_and_usage_report_athena_table"

  table_type = "EXTERNAL_TABLE"

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  storage_descriptor {
    location          = "s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/"
    input_format      = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format     = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed        = false
    number_of_buckets = -1

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" : "1"
      }
    }

    parameters = {
      CrawlerSchemaDeserializerVersion = "1.0"
      CrawlerSchemaSerializerVersion   = "1.0"
      UPDATED_BY_CRAWLER               = aws_glue_crawler.aws_cur_crawler_cost_and_usage_report.name
      classification                   = "parquet"
      compressionType                  = "none"
      exclusions                       = "[\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.json\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.yml\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.sql\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.csv\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.gz\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.zip\"]"
      typeOfData                       = "file"
    }
  }

  parameters = {
    CrawlerSchemaDeserializerVersion = "1.0"
    CrawlerSchemaSerializerVersion   = "1.0"
    UPDATED_BY_CRAWLER               = aws_glue_crawler.aws_cur_crawler_cost_and_usage_report.name
    classification                   = "parquet"
    compressionType                  = "none"
    exclusions                       = "[\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.json\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.yml\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.sql\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.csv\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.gz\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.mgmt_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.zip\"]"
    typeOfData                       = "file"
  }

}
