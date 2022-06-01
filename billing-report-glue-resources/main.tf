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
  description             = "CMK key for resources related to ${local.app_name}"
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
  acl           = "private"
  force_destroy = false

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
            "arn:aws:iam::${var.operator_account_id}:root", // Change to line below after deployment to LZ0 Operations account
            #            "arn:aws:iam::${var.operator_account_id}:role/octk-aws-sea-billing-reports-TaskRole",
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
# Grant Operator account access to assume role via STS
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
            "arn:aws:iam::${var.operator_account_id}:root", // Maybe change to line below after deployment to LZ Operations account
            #            "arn:aws:iam::${var.operator_account_id}:role/octk-aws-sea-billing-reports-TaskRole",
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
        Resource = "arn:aws:s3:::pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report*"
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
  name = "athenacurcfn_cost_and_usage_report"
}


resource "aws_glue_crawler" "aws_cur_crawler_cost_and_usage_report" {
  name          = "AWSCURCrawler-Cost-and-Usage-Report"
  role          = aws_iam_role.athena_cost_and_usage_report.arn
  database_name = aws_glue_catalog_database.athenacurcfn_cost_and_usage_report_database.name
  description   = "A recurring crawler that keeps your CUR table in Athena up-to-date."

  s3_target {
    path = "s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/"
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
  name          = "cost_and_usage_report"

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
    location          = "s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/"
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
      exclusions                       = "[\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.json\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.yml\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.sql\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.csv\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.gz\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.zip\"]"
      typeOfData                       = "file"
    }

    columns {
      name = "identity_line_item_id"
      type = "string"
    }
    columns {
      name = "identity_time_interval"
      type = "string"
    }
    columns {
      name = "bill_invoice_id"
      type = "string"
    }
    columns {
      name = "bill_billing_entity"
      type = "string"
    }
    columns {
      name = "bill_bill_type"
      type = "string"
    }
    columns {
      name = "bill_payer_account_id"
      type = "string"
    }
    columns {
      name = "bill_billing_period_start_date"
      type = "timestamp"
    }
    columns {
      name = "bill_billing_period_end_date"
      type = "timestamp"
    }
    columns {
      name = "line_item_usage_account_id"
      type = "string"
    }
    columns {
      name = "line_item_line_item_type"
      type = "string"
    }
    columns {
      name = "line_item_usage_start_date"
      type = "timestamp"
    }
    columns {
      name = "line_item_usage_end_date"
      type = "timestamp"
    }
    columns {
      name = "line_item_product_code"
      type = "string"
    }
    columns {
      name = "line_item_usage_type"
      type = "string"
    }
    columns {
      name = "line_item_operation"
      type = "string"
    }
    columns {
      name = "line_item_availability_zone"
      type = "string"
    }
    columns {
      name = "line_item_resource_id"
      type = "string"
    }
    columns {
      name = "line_item_usage_amount"
      type = "double"
    }
    columns {
      name = "line_item_normalization_factor"
      type = "double"
    }
    columns {
      name = "line_item_normalized_usage_amount"
      type = "double"
    }
    columns {
      name = "line_item_currency_code"
      type = "string"
    }
    columns {
      name = "line_item_unblended_rate"
      type = "string"
    }
    columns {
      name = "line_item_unblended_cost"
      type = "double"
    }
    columns {
      name = "line_item_blended_rate"
      type = "string"
    }
    columns {
      name = "line_item_blended_cost"
      type = "double"
    }
    columns {
      name = "line_item_line_item_description"
      type = "string"
    }
    columns {
      name = "line_item_tax_type"
      type = "string"
    }
    columns {
      name = "line_item_legal_entity"
      type = "string"
    }
    columns {
      name = "product_product_name"
      type = "string"
    }
    columns {
      name = "product_alarm_type"
      type = "string"
    }
    columns {
      name = "product_attachment_type"
      type = "string"
    }
    columns {
      name = "product_availability"
      type = "string"
    }
    columns {
      name = "product_capacitystatus"
      type = "string"
    }
    columns {
      name = "product_clock_speed"
      type = "string"
    }
    columns {
      name = "product_compute_family"
      type = "string"
    }
    columns {
      name = "product_compute_type"
      type = "string"
    }
    columns {
      name = "product_cputype"
      type = "string"
    }
    columns {
      name = "product_current_generation"
      type = "string"
    }
    columns {
      name = "product_dedicated_ebs_throughput"
      type = "string"
    }
    columns {
      name = "product_description"
      type = "string"
    }
    columns {
      name = "product_durability"
      type = "string"
    }
    columns {
      name = "product_ecu"
      type = "string"
    }
    columns {
      name = "product_endpoint_type"
      type = "string"
    }
    columns {
      name = "product_enhanced_networking_supported"
      type = "string"
    }
    columns {
      name = "product_finding_group"
      type = "string"
    }
    columns {
      name = "product_finding_source"
      type = "string"
    }
    columns {
      name = "product_finding_storage"
      type = "string"
    }
    columns {
      name = "product_from_location"
      type = "string"
    }
    columns {
      name = "product_from_location_type"
      type = "string"
    }
    columns {
      name = "product_group"
      type = "string"
    }
    columns {
      name = "product_group_description"
      type = "string"
    }
    columns {
      name = "product_insightstype"
      type = "string"
    }
    columns {
      name = "product_instance_family"
      type = "string"
    }
    columns {
      name = "product_instance_type"
      type = "string"
    }
    columns {
      name = "product_instance_type_family"
      type = "string"
    }
    columns {
      name = "product_intel_avx2_available"
      type = "string"
    }
    columns {
      name = "product_intel_avx_available"
      type = "string"
    }
    columns {
      name = "product_intel_turbo_available"
      type = "string"
    }
    columns {
      name = "product_license_model"
      type = "string"
    }
    columns {
      name = "product_location"
      type = "string"
    }
    columns {
      name = "product_location_type"
      type = "string"
    }
    columns {
      name = "product_logs_destination"
      type = "string"
    }
    columns {
      name = "product_max_iops_burst_performance"
      type = "string"
    }
    columns {
      name = "product_max_iopsvolume"
      type = "string"
    }
    columns {
      name = "product_max_throughputvolume"
      type = "string"
    }
    columns {
      name = "product_max_volume_size"
      type = "string"
    }
    columns {
      name = "product_maximum_extended_storage"
      type = "string"
    }
    columns {
      name = "product_memory"
      type = "string"
    }
    columns {
      name = "product_memorytype"
      type = "string"
    }
    columns {
      name = "product_message_delivery_frequency"
      type = "string"
    }
    columns {
      name = "product_message_delivery_order"
      type = "string"
    }
    columns {
      name = "product_network_performance"
      type = "string"
    }
    columns {
      name = "product_normalization_size_factor"
      type = "string"
    }
    columns {
      name = "product_operating_system"
      type = "string"
    }
    columns {
      name = "product_operation"
      type = "string"
    }
    columns {
      name = "product_parameter_type"
      type = "string"
    }
    columns {
      name = "product_physical_processor"
      type = "string"
    }
    columns {
      name = "product_pre_installed_sw"
      type = "string"
    }
    columns {
      name = "product_processor_architecture"
      type = "string"
    }
    columns {
      name = "product_processor_features"
      type = "string"
    }
    columns {
      name = "product_product_family"
      type = "string"
    }
    columns {
      name = "product_queue_type"
      type = "string"
    }
    columns {
      name = "product_ratetype"
      type = "string"
    }
    columns {
      name = "product_region"
      type = "string"
    }
    columns {
      name = "product_routing_target"
      type = "string"
    }
    columns {
      name = "product_routing_type"
      type = "string"
    }
    columns {
      name = "product_servicecode"
      type = "string"
    }
    columns {
      name = "product_servicename"
      type = "string"
    }
    columns {
      name = "product_sku"
      type = "string"
    }
    columns {
      name = "product_standard_group"
      type = "string"
    }
    columns {
      name = "product_standard_storage"
      type = "string"
    }
    columns {
      name = "product_standard_storage_retention_included"
      type = "string"
    }
    columns {
      name = "product_storage"
      type = "string"
    }
    columns {
      name = "product_storage_class"
      type = "string"
    }
    columns {
      name = "product_storage_media"
      type = "string"
    }
    columns {
      name = "product_storage_type"
      type = "string"
    }
    columns {
      name = "product_tenancy"
      type = "string"
    }
    columns {
      name = "product_throughput"
      type = "string"
    }
    columns {
      name = "product_to_location"
      type = "string"
    }
    columns {
      name = "product_to_location_type"
      type = "string"
    }
    columns {
      name = "product_transfer_type"
      type = "string"
    }
    columns {
      name = "product_usagetype"
      type = "string"
    }
    columns {
      name = "product_vcpu"
      type = "string"
    }
    columns {
      name = "product_version"
      type = "string"
    }
    columns {
      name = "product_volume_api_name"
      type = "string"
    }
    columns {
      name = "product_volume_type"
      type = "string"
    }
    columns {
      name = "pricing_rate_id"
      type = "string"
    }
    columns {
      name = "pricing_currency"
      type = "string"
    }
    columns {
      name = "pricing_public_on_demand_cost"
      type = "double"
    }
    columns {
      name = "pricing_public_on_demand_rate"
      type = "string"
    }
    columns {
      name = "pricing_term"
      type = "string"
    }
    columns {
      name = "pricing_unit"
      type = "string"
    }
    columns {
      name = "reservation_amortized_upfront_cost_for_usage"
      type = "double"
    }
    columns {
      name = "reservation_amortized_upfront_fee_for_billing_period"
      type = "double"
    }
    columns {
      name = "reservation_effective_cost"
      type = "double"
    }
    columns {
      name = "reservation_end_time"
      type = "string"
    }
    columns {
      name = "reservation_modification_status"
      type = "string"
    }
    columns {
      name = "reservation_normalized_units_per_reservation"
      type = "string"
    }
    columns {
      name = "reservation_number_of_reservations"
      type = "string"
    }
    columns {
      name = "reservation_recurring_fee_for_usage"
      type = "double"
    }
    columns {
      name = "reservation_start_time"
      type = "string"
    }
    columns {
      name = "reservation_subscription_id"
      type = "string"
    }
    columns {
      name = "reservation_total_reserved_normalized_units"
      type = "string"
    }
    columns {
      name = "reservation_total_reserved_units"
      type = "string"
    }
    columns {
      name = "reservation_units_per_reservation"
      type = "string"
    }
    columns {
      name = "reservation_unused_amortized_upfront_fee_for_billing_period"
      type = "double"
    }
    columns {
      name = "reservation_unused_normalized_unit_quantity"
      type = "double"
    }
    columns {
      name = "reservation_unused_quantity"
      type = "double"
    }
    columns {
      name = "reservation_unused_recurring_fee"
      type = "double"
    }
    columns {
      name = "reservation_upfront_value"
      type = "double"
    }
    columns {
      name = "savings_plan_total_commitment_to_date"
      type = "double"
    }
    columns {
      name = "savings_plan_savings_plan_a_r_n"
      type = "string"
    }
    columns {
      name = "savings_plan_savings_plan_rate"
      type = "double"
    }
    columns {
      name = "savings_plan_used_commitment"
      type = "double"
    }
    columns {
      name = "savings_plan_savings_plan_effective_cost"
      type = "double"
    }
    columns {
      name = "savings_plan_amortized_upfront_commitment_for_billing_period"
      type = "double"
    }
    columns {
      name = "savings_plan_recurring_commitment_for_billing_period"
      type = "double"
    }
    columns {
      name = "product_with_active_users"
      type = "string"
    }
    columns {
      name = "product_availability_zone"
      type = "string"
    }
    columns {
      name = "product_category"
      type = "string"
    }
    columns {
      name = "product_ci_type"
      type = "string"
    }
    columns {
      name = "product_classicnetworkingsupport"
      type = "string"
    }
    columns {
      name = "product_content_type"
      type = "string"
    }
    columns {
      name = "product_database_engine"
      type = "string"
    }
    columns {
      name = "product_datatransferout"
      type = "string"
    }
    columns {
      name = "product_deployment_option"
      type = "string"
    }
    columns {
      name = "product_engine"
      type = "string"
    }
    columns {
      name = "product_engine_code"
      type = "string"
    }
    columns {
      name = "product_equivalentondemandsku"
      type = "string"
    }
    columns {
      name = "product_free_query_types"
      type = "string"
    }
    columns {
      name = "product_from_region_code"
      type = "string"
    }
    columns {
      name = "product_marketoption"
      type = "string"
    }
    columns {
      name = "product_memory_gib"
      type = "string"
    }
    columns {
      name = "product_min_volume_size"
      type = "string"
    }
    columns {
      name = "product_origin"
      type = "string"
    }
    columns {
      name = "product_platopricingtype"
      type = "string"
    }
    columns {
      name = "product_platostoragetype"
      type = "string"
    }
    columns {
      name = "product_platousagetype"
      type = "string"
    }
    columns {
      name = "product_recipient"
      type = "string"
    }
    columns {
      name = "product_region_code"
      type = "string"
    }
    columns {
      name = "product_request_description"
      type = "string"
    }
    columns {
      name = "product_request_type"
      type = "string"
    }
    columns {
      name = "product_steps"
      type = "string"
    }
    columns {
      name = "product_to_region_code"
      type = "string"
    }
    columns {
      name = "product_vpcnetworkingsupport"
      type = "string"
    }
    columns {
      name = "pricing_rate_code"
      type = "string"
    }
    columns {
      name = "bill_invoicing_entity"
      type = "string"
    }
    columns {
      name = "product_backupservice"
      type = "string"
    }
    columns {
      name = "product_describes"
      type = "string"
    }
    columns {
      name = "product_gets"
      type = "string"
    }
    columns {
      name = "product_ops_items"
      type = "string"
    }
    columns {
      name = "product_pricing_unit"
      type = "string"
    }
    columns {
      name = "product_updates"
      type = "string"
    }
    columns {
      name = "product_metering_type"
      type = "string"
    }
    columns {
      name = "product_database_edition"
      type = "string"
    }
  }

  parameters = {
    CrawlerSchemaDeserializerVersion = "1.0"
    CrawlerSchemaSerializerVersion   = "1.0"
    UPDATED_BY_CRAWLER               = aws_glue_crawler.aws_cur_crawler_cost_and_usage_report.name
    classification                   = "parquet"
    compressionType                  = "none"
    exclusions                       = "[\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.json\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.yml\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.sql\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.csv\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.gz\",\"s3://pbmmaccel-master-phase1-cacentral1-${var.master_account_phase1_bucket_suffix}/${data.aws_caller_identity.current.account_id}}/cur/Cost-and-Usage-Report/Cost-and-Usage-Report/**.zip\"]"
    typeOfData                       = "file"
  }

}