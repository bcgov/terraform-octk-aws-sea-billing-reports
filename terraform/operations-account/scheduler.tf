resource "aws_scheduler_schedule_group" "billing_reports" {
  name = "${local.app_name}-billing-reports"
}


# Billing reports weekly schedule
resource "aws_scheduler_schedule" "billing_reports_weekly" {
  name                         = "${local.app_name}-weekly-schedule"
  group_name                   = aws_scheduler_schedule_group.billing_reports.name
  description                  = "Execute the ${local.app_name} every Thursday at noon (Pacific time)"
  schedule_expression          = "cron(0 12 ? * THU *)"
  schedule_expression_timezone = "America/Vancouver"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_ecs_cluster.billing_reports_ecs_cluster.arn
    role_arn = aws_iam_role.ecs_event_bridge_role.arn

    input = jsonencode({
      containerOverrides = [{
        name = "${local.app_name}-ecs-container-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
        "environment" = [
          {
            "name"  = "REPORT_TYPE",
            "value" = "Weekly"
          },
          {
            "name"  = "GROUP_TYPE",
            "value" = "billing_group"
          },
          {
            "name"  = "DELIVER",
            "value" = "True"
          },
          {
            "name"  = "RECIPIENT_OVERRIDE",
            "value" = ""
          },
          {
            "name"  = "CARBON_COPY",
            "value" = "cloud.pathfinder@gov.bc.ca"
          },
          {
            "name"  = "ATHENA_QUERY_OUTPUT_BUCKET",
            "value" = "bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
          },
          {
            "name"  = "ATHENA_QUERY_OUTPUT_BUCKET_ARN",
            "value" = "arn:aws:s3:::bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
          },
          {
            "name"  = "ATHENA_QUERY_ROLE_TO_ASSUME_ARN",
            "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report"
          },
          {
            "name"  = "QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN",
            "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
          },
          {
            "name"  = "ATHENA_QUERY_DATABASE",
            "value" = "cost_and_usage_report_athena_db"
          },
          {
            "name"  = "CMK_SSE_KMS_ALIAS",
            "value" = "arn:aws:kms:ca-central-1:${var.lz_mgmt_account_id}:alias/BCGov-BillingReports"
          }
        ]
      }]
    })

    ecs_parameters {
      task_count          = 1
      task_definition_arn = aws_ecs_task_definition.billing_reports_ecs_task.arn
      launch_type         = "FARGATE"
      platform_version    = "LATEST"

      network_configuration {
        security_groups  = [aws_security_group.billing_reports_ecs_task_sg.id]
        subnets          = [for subnet in data.aws_subnets.current.ids : subnet]
        assign_public_ip = true
      }

      propagate_tags = "TASK_DEFINITION"
    }
  }
}


# Billing Monthly schedule 
resource "aws_scheduler_schedule" "billing_reports_monthly" {
  name                         = "${local.app_name}-monthly-schedule"
  group_name                   = aws_scheduler_schedule_group.billing_reports.name
  description                  = "Execute the ${local.app_name} at noon on the first day every month (legacy cron kept as-is)"
  schedule_expression          = "cron(0 12 1 * ? *)"
  schedule_expression_timezone = "America/Vancouver"
  state                        = "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_ecs_cluster.billing_reports_ecs_cluster.arn
    role_arn = aws_iam_role.ecs_event_bridge_role.arn

    input = jsonencode({
      containerOverrides = [{
        name = "${local.app_name}-ecs-container-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
        "environment" = [
          {
            "name"  = "REPORT_TYPE",
            "value" = "Monthly"
          },
          {
            "name"  = "GROUP_TYPE",
            "value" = "billing_group"
          },
          {
            "name"  = "DELIVER",
            "value" = "True"
          },
          {
            "name"  = "RECIPIENT_OVERRIDE",
            "value" = ""
          },
          {
            "name"  = "CARBON_COPY",
            "value" = "cloud.pathfinder@gov.bc.ca"
          },
          {
            "name"  = "ATHENA_QUERY_OUTPUT_BUCKET",
            "value" = "bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
          },
          {
            "name"  = "ATHENA_QUERY_OUTPUT_BUCKET_ARN",
            "value" = "arn:aws:s3:::bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
          },
          {
            "name"  = "ATHENA_QUERY_ROLE_TO_ASSUME_ARN",
            "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report"
          },
          {
            "name"  = "QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN",
            "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
          },
          {
            "name"  = "ATHENA_QUERY_DATABASE",
            "value" = "cost_and_usage_report_athena_db"
          },
          {
            "name"  = "CMK_SSE_KMS_ALIAS",
            "value" = "arn:aws:kms:ca-central-1:${var.lz_mgmt_account_id}:alias/BCGov-BillingReports"
          }
        ]
      }]
    })

    ecs_parameters {
      task_count          = 1
      task_definition_arn = aws_ecs_task_definition.billing_reports_ecs_task.arn
      launch_type         = "FARGATE"
      platform_version    = "LATEST"

      network_configuration {
        security_groups  = [aws_security_group.billing_reports_ecs_task_sg.id]
        subnets          = [for subnet in data.aws_subnets.current.ids : subnet]
        assign_public_ip = true
      }

      propagate_tags = "TASK_DEFINITION"
    }
  }
}

# Billing quarterly schedule 
resource "aws_scheduler_schedule" "billing_reports_quarterly" {
  name        = "${local.app_name}-quarterly"
  group_name  = aws_scheduler_schedule_group.billing_reports.name
  description = "Execute the ${local.app_name} quarterly at midnight Pacific time"
  # 2AM local time, quarterly on Jan/Apr/Jul/Oct 1st
  schedule_expression          = "cron(0 2 1 1/3 ? *)"
  schedule_expression_timezone = "America/Vancouver"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_ecs_cluster.billing_reports_ecs_cluster.arn
    role_arn = aws_iam_role.ecs_event_bridge_role.arn

    input = jsonencode({
      containerOverrides = [{
        name = "${local.app_name}-ecs-container-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
        "environment" = [
          {
            "name"  = "REPORT_TYPE",
            "value" = "Quarterly"
          },
          {
            "name"  = "GROUP_TYPE",
            "value" = "account_coding"
          },
          {
            "name"  = "DELIVER",
            "value" = "True"
          },
          {
            "name"  = "RECIPIENT_OVERRIDE",
            "value" = "cloud.pathfinder@gov.bc.ca"
          },
          {
            "name"  = "CARBON_COPY",
            "value" = "Rosemarie.Segura@gov.bc.ca"
          },
          {
            "name"  = "ATHENA_QUERY_OUTPUT_BUCKET",
            "value" = "bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
          },
          {
            "name"  = "ATHENA_QUERY_OUTPUT_BUCKET_ARN",
            "value" = "arn:aws:s3:::bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
          },
          {
            "name"  = "ATHENA_QUERY_ROLE_TO_ASSUME_ARN",
            "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report"
          },
          {
            "name"  = "QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN",
            "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
          },
          {
            "name"  = "ATHENA_QUERY_DATABASE",
            "value" = "cost_and_usage_report_athena_db"
          },
          {
            "name"  = "CMK_SSE_KMS_ALIAS",
            "value" = "arn:aws:kms:ca-central-1:${var.lz_mgmt_account_id}:alias/BCGov-BillingReports"
          },
          {
            "name"  = "QR_S3_Bucket",
            "value" = "${aws_s3_bucket.quarterly_reports_bucket.bucket}"
          }
        ]
      }]
    })

    ecs_parameters {
      task_count          = 1
      task_definition_arn = aws_ecs_task_definition.billing_reports_ecs_task.arn
      launch_type         = "FARGATE"
      platform_version    = "LATEST"

      network_configuration {
        security_groups  = [aws_security_group.billing_reports_ecs_task_sg.id]
        subnets          = [for subnet in data.aws_subnets.current.ids : subnet]
        assign_public_ip = true
      }

      propagate_tags = "TASK_DEFINITION"
    }
  }
}


resource "aws_cloudwatch_metric_alarm" "billing_reports_scheduler_target_errors" {
  alarm_name          = "${local.app_name} - Scheduler target errors"
  alarm_description   = "Scheduler attempted to invoke the target but the target returned an error"
  namespace           = "AWS/Scheduler"
  metric_name         = "TargetErrorCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ScheduleGroup = aws_scheduler_schedule_group.billing_reports.name
  }
}
