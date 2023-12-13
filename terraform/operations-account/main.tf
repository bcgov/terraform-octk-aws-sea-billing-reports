terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_vpc" "current" {}

data "aws_subnet_ids" "current" {
  vpc_id = data.aws_vpc.current.id

  tags = {
    Name = "App_Central*"
  }
}

locals {
  app_name = "octk-aws-sea-billing-reports"
}

resource "aws_ses_email_identity" "source_email_address" {
  email = "info@cloud.gov.bc.ca"
}

resource "aws_ecr_repository" "billing_reports_ecr" {
  name                 = "${local.app_name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "billing_reports_ecr_lifecycle_policy" {
  repository = aws_ecr_repository.billing_reports_ecr.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 5 images"
      action = {
        type = "expire"
      }
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
    }]
  })
}

resource "aws_ecr_repository_policy" "billing_reports_ecr_policy" {
  repository = aws_ecr_repository.billing_reports_ecr.name
  policy = jsonencode({
    Version = "2008-10-17",
    Statement = [{
      Sid = "ECRAccessToBillingReportRepo",
      Effect : "Allow",
      Principal : "*",
      Action : [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories",
        "ecr:GetAuthorizationToken",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:ListImages",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
    }]
  })
}

output "ecr_repo" {
  value = aws_ecr_repository.billing_reports_ecr.repository_url
}

resource "null_resource" "docker_build" {

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      assume_org_role=$(aws sts assume-role --role-arn arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSCloudFormationStackSetExecutionRole --role-session-name AWSCLI-Session)
      echo -e "[profile org_role]\naws_access_key_id = $(echo $assume_org_role | jq -r .Credentials.AccessKeyId)\naws_secret_access_key = $(echo $assume_org_role | jq -r .Credentials.SecretAccessKey)\naws_session_token = $(echo $assume_org_role | jq -r .Credentials.SessionToken)" > aws_credentials
      export DOCKER_BUILDKIT=0
      export COMPOSE_DOCKER_CLI_BUILD=0
      AWS_CONFIG_FILE="./aws_credentials" aws ecr get-login-password --region ${data.aws_region.current.name} --profile org_role | docker login \
        --username AWS \
        --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
      docker build -t ${local.app_name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name} -f Dockerfile .
      docker tag ${local.app_name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}:latest ${aws_ecr_repository.billing_reports_ecr.repository_url}:latest
      docker push ${aws_ecr_repository.billing_reports_ecr.repository_url}:latest
    EOT
  }
}

// ECS task access policies
resource "aws_iam_policy" "ecs_task_access_policies" {
  name = "${local.app_name}-access-policies"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3RelatedPermissions"
        Effect = "Allow",
        Action = [
          "s3:Get*",
          "s3:List*"
        ],
        Resource = ["*"] // TODO: Too relaxed. Need to revise for LZ deployment
      },
      {
        Sid    = "SecretsRelatedPermissions"
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = ["*"] // TODO: Too relaxed. Need to revise for LZ deployment
      },
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "kms:Decrypt",
          "kms:Encrypt",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ],
        "Resource" : [
          "arn:aws:kms:ca-central-1:${data.aws_caller_identity.current.account_id}:key/*",
          "arn:aws:ssm:ca-central-1:${data.aws_caller_identity.current.account_id}:parameter/bcgov/billingutility/teams_alert_webhook",
          "arn:aws:ssm:ca-central-1:${data.aws_caller_identity.current.account_id}:parameter/bcgov/billingutility/rocketchat_alert_webhook"
        ]
      },
      {
        "Sid" : "VisualEditor1",
        "Effect" : "Allow",
        "Action" : "ssm:DescribeParameters",
        "Resource" : "*"
      },
      {
        Sid    = "CloudWatchLogsRelatedPermissions"
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Resource = ["arn:aws:logs:*:*:*"] // TODO: Too relaxed. Need to revise for LZ deployment
      },
      {
        Sid : "SESRelatedPermissions"
        Effect : "Allow",
        Action : [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource : ["arn:aws:ses:ca-central-1:${data.aws_caller_identity.current.account_id}:identity/*"]
      },
      {
        "Sid" : "AssumeAthenaCostRoleOnMasterAccount",
        "Effect" : "Allow",
        "Action" : "sts:AssumeRole",
        "Resource" : "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report"
      },
      {
        "Sid" : "AssumeQueryOrgAccountsRoleOnMasterAccount",
        "Effect" : "Allow",
        "Action" : "sts:AssumeRole",
        "Resource" : "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${local.app_name}-TaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Sid    = ""
        Principal = {
          Service = [
            "ecs-tasks.amazonaws.com"
          ]
        },
      }
    ]
  })
}

// Attach ECS task policies to ECS task role
resource "aws_iam_role_policy_attachment" "ecs_task_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_access_policies.arn
}

// ECS task access policies
resource "aws_iam_policy" "ecs_task_exec_policies" {
  name = "${local.app_name}-exec-policies"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsRelatedPermissions"
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = ["*"] // TODO: Too relaxed. Need to revise for LZ deployment
      },
      {
        Sid    = "CloudWatchLogsRelatedPermissions"
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Resource = ["arn:aws:logs:*:*:*"] // TODO: Too relaxed. Need to revise for LZ deployment
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_exec_role" {
  name = "${local.app_name}-TaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Sid    = ""
        Principal = {
          Service = [
            "ecs-tasks.amazonaws.com"
          ]
        },
      }
    ]
  })
}

# Attached AWS managed policy to allow Task Exec Role work with CloudWatch and ECR
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy_attachement" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attached policy needed by Task Execution Role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_access" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = aws_iam_policy.ecs_task_exec_policies.arn
}

// TODO: Review updating this to block ingress connections if not addressed by the SEA
resource "aws_security_group" "billing_reports_ecs_task_sg" {
  name   = "${local.app_name}-task-sg"
  vpc_id = data.aws_vpc.current.id

  egress {
    from_port        = 0
    protocol         = "-1"
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_ecs_cluster" "billing_reports_ecs_cluster" {
  name = "${local.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# adding the event bridge rule failure alerts
resource "aws_cloudwatch_event_rule" "ecs_task_state_change" {
  name        = "ecs-task-state-change"
  description = "Triggers on ECS task state changes from RUNNING to STOPPED for ${local.app_name}-cluster"

  event_pattern = jsonencode({
    source: ["aws.ecs"],
    "detail-type": ["ECS Task State Change"],
    detail: {
      clusterArn: [aws_ecs_cluster.billing_reports_ecs_cluster.arn],
      lastStatus: ["STOPPED"],
      desiredStatus: ["STOPPED"]
    }
  })
}


resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.ecs_task_state_change.name
  target_id = "TargetFunctionV1"
  arn       = var.lambda_arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecs_task_state_change.arn
}

resource "aws_ecs_task_definition" "billing_reports_ecs_task" {
  family                   = "${local.app_name}-ecs-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "8192"  # This needs to be high for the quarterly billing report to run to completion
  memory                   = "32768" # This needs to be high for the quarterly billing report to run to completion
  execution_role_arn       = aws_iam_role.ecs_task_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
      # cpu_architecture        = "ARM64" // Used when testing deployment from Local ARM64 based device
  }
  container_definitions = jsonencode([{
    name       = "${local.app_name}-ecs-container-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
    image      = "${aws_ecr_repository.billing_reports_ecr.repository_url}:latest"
    entryPoint = ["python3", "billing.py"]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = "/ecs/${local.app_name}-ecs-task",
        awslogs-region        = data.aws_region.current.name,
        awslogs-create-group  = "true",
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_iam_role" "ecs_event_bridge_role" {
  name = "${local.app_name}-ecs-event-bridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = [
            "events.amazonaws.com"
          ]
        },
      }
    ]
  })
}

// Attach ECS task access policies to EventBridge role
resource "aws_iam_role_policy_attachment" "eventbridge_ecs_task_access" {
  role       = aws_iam_role.ecs_event_bridge_role.name
  policy_arn = aws_iam_policy.ecs_task_access_policies.arn
}

resource "aws_iam_role_policy_attachment" "eventbridge_ecs_task_execution_policy_attachement" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_event_bridge_access_policies" {
  name = "${local.app_name}-ecs_event_bridge_access_policies"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = ["ecs:RunTask"],
        Resource = [
          "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:task-definition/*"
        ]
        Condition = {
          "StringLike" = {
            "ecs:cluster" = "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:cluster/*"
          }
        }
      },
      {
        Effect   = "Allow",
        Action   = "iam:PassRole",
        Resource = ["*"]
        Condition = {
          "StringLike" = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_event_bridge_access" {
  role       = aws_iam_role.ecs_event_bridge_role.name
  policy_arn = aws_iam_policy.ecs_event_bridge_access_policies.arn
}

resource "aws_cloudwatch_event_rule" "billing_reports_weekly_rule" {
  name                = "${local.app_name}-weekly-rule"
  description         = "Execute the ${local.app_name} every Friday at noon" // Note: 1900 UTC is 1200 PST
  schedule_expression = "cron(0 19 ? * THUR *)"
  is_enabled          = true
}

resource "aws_cloudwatch_event_target" "billing_reports_weekly_target" {
  target_id = "${local.app_name}-weekly-targer"
  arn       = aws_ecs_cluster.billing_reports_ecs_cluster.arn
  role_arn  = aws_iam_role.ecs_event_bridge_role.arn
  rule      = aws_cloudwatch_event_rule.billing_reports_weekly_rule.name

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
          "name"  = "DELIVER", # for manual runs/ testing
          "value" = "True"
        },
        {
          "name"  = "RECIPIENT_OVERRIDE", # for manual runs/ testing
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
          "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report",
        },
        {
          "name"  = "QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN",
          "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
        },
        {
          "name"  = "ATHENA_QUERY_DATABASE",
          "value" = "cost_and_usage_report_athena_db",
        },
        {
          "name"  = "CMK_SSE_KMS_ALIAS"
          "value" = "arn:aws:kms:ca-central-1:${var.lz_mgmt_account_id}:alias/BCGov-BillingReports"
        }
      ],
    }]
  })
  ecs_target {
    task_count              = 1
    task_definition_arn     = aws_ecs_task_definition.billing_reports_ecs_task.arn
    launch_type             = "FARGATE"
    platform_version        = "LATEST"
    enable_execute_command  = false
    enable_ecs_managed_tags = false

    network_configuration {
      security_groups = [aws_security_group.billing_reports_ecs_task_sg.id]
      subnets         = [for subnet in data.aws_subnet_ids.current.ids : subnet]
      // TODO: Can you make this false and revise to use NAT for access to ECR and CloudWatch???
      assign_public_ip = true
    }
  }
}

resource "aws_cloudwatch_event_rule" "billing_reports_monthly_rule" {
  name                = "${local.app_name}-monthly-rule"
  description         = "Execute the ${local.app_name} at noon on the first day every month" // Note: 1900 UTC is 1200 PST
  schedule_expression = "cron(0 19 1 * ? *)"
  is_enabled          = false
}

resource "aws_cloudwatch_event_target" "billing_reports_monthly_target" {
  target_id = "${local.app_name}-monthly-targer"
  arn       = aws_ecs_cluster.billing_reports_ecs_cluster.arn
  role_arn  = aws_iam_role.ecs_event_bridge_role.arn
  rule      = aws_cloudwatch_event_rule.billing_reports_monthly_rule.name

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
          "name"  = "DELIVER", # for manual runs/ testing
          "value" = "True"
        },
        {
          "name"  = "RECIPIENT_OVERRIDE", # for manual runs/ testing
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
          "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report",
        },
        {
          "name"  = "QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN",
          "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
        },
        {
          "name"  = "ATHENA_QUERY_DATABASE",
          "value" = "cost_and_usage_report_athena_db",
        },
        {
          "name"  = "CMK_SSE_KMS_ALIAS"
          "value" = "arn:aws:kms:ca-central-1:${var.lz_mgmt_account_id}:alias/BCGov-BillingReports"
        }
      ],
    }]
  })
  ecs_target {
    task_count              = 1
    task_definition_arn     = aws_ecs_task_definition.billing_reports_ecs_task.arn
    launch_type             = "FARGATE"
    platform_version        = "LATEST"
    enable_execute_command  = false
    enable_ecs_managed_tags = false

    network_configuration {
      security_groups = [aws_security_group.billing_reports_ecs_task_sg.id]
      subnets         = [for subnet in data.aws_subnet_ids.current.ids : subnet]
      // TODO: Can you make this false and revise to use NAT for access to ECR and CloudWatch???
      assign_public_ip = true
    }
  }
}

resource "aws_cloudwatch_event_rule" "billing_reports_quarterly_rule" {
  name                = "${local.app_name}-quarterly-rule"
  description         = "Execute the ${local.app_name} quarterly" // Note: 1900 UTC is 1200 PST
  schedule_expression = "cron(0 19 1 1/3 ? *)"
  is_enabled          = true
}

resource "aws_cloudwatch_event_target" "billing_reports_quarterly_target" {
  target_id = "${local.app_name}-quarterly-targer"
  arn       = aws_ecs_cluster.billing_reports_ecs_cluster.arn
  role_arn  = aws_iam_role.ecs_event_bridge_role.arn
  rule      = aws_cloudwatch_event_rule.billing_reports_quarterly_rule.name

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
          "name"  = "DELIVER", # for manual runs/ testing
          "value" = "True"
        },
        {
          "name"  = "RECIPIENT_OVERRIDE", # Quarterly runs should not be sent to clients
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
          "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report",
        },
        {
          "name"  = "QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN",
          "value" = "arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
        },
        {
          "name"  = "ATHENA_QUERY_DATABASE",
          "value" = "cost_and_usage_report_athena_db",
        },
        {
          "name"  = "CMK_SSE_KMS_ALIAS"
          "value" = "arn:aws:kms:ca-central-1:${var.lz_mgmt_account_id}:alias/BCGov-BillingReports"
        }
      ],
    }]
  })
  ecs_target {
    task_count              = 1
    task_definition_arn     = aws_ecs_task_definition.billing_reports_ecs_task.arn
    launch_type             = "FARGATE"
    platform_version        = "LATEST"
    enable_execute_command  = false
    enable_ecs_managed_tags = false

    network_configuration {
      security_groups = [aws_security_group.billing_reports_ecs_task_sg.id]
      subnets         = [for subnet in data.aws_subnet_ids.current.ids : subnet]
      // TODO: Can you make this false and revise to use NAT for access to ECR and CloudWatch???
      assign_public_ip = true
    }
  }
}

resource "aws_ssm_parameter" "manual_run_environment_variables" {
  name  = "/bcgov/billingutility/manual_run/env_vars"
  type  = "SecureString"
  value = <<EOT
    export REPORT_TYPE="Manual"
    export GROUP_TYPE="billing_group"
    export START_DATE=""
    export END_DATE=""
    export DELIVER="False"
    export RECIPIENT_OVERRIDE="your.email@here.ca"
    export CARBON_COPY=""
    export ATHENA_QUERY_ROLE_TO_ASSUME_ARN="arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Athena-Cost-and-Usage-Report"
    export ATHENA_QUERY_DATABASE="cost_and_usage_report_athena_db
    export QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN="arn:aws:iam::${var.lz_mgmt_account_id}:role/BCGov-Query-Org-Accounts"
    export ATHENA_QUERY_OUTPUT_BUCKET="bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
    export ATHENA_QUERY_OUTPUT_BUCKET_ARN="arn:aws:s3:::bcgov-ecf-billing-reports-output-${var.lz_mgmt_account_id}-ca-central-1"
    export CMK_SSE_KMS_ALIAS="arn:aws:kms:ca-central-1:${var.lz_mgmt_account_id}:alias/BCGov-BillingReports"
  EOT
}
