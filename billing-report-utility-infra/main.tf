terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      // Moved from 3.48.0 to 3.70 due to runtime_platform bug file
      // https://github.com/hashicorp/terraform-provider-aws/issues/22153
      // https://github.com/hashicorp/terraform-provider-aws/blob/v3.70.0/CHANGELOG.md
      version = "~> 3.70.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"

  #  backend "s3" {
  #    bucket = "S3-bucket-for-state-files" // eg: bcgov-ecf-billing-reports-tfrb-1234567891-ca-central-1
  #    key    = "tfrb-aws/operations/terraform.tfstate"
  #    region = "ca-central-1"
  #
  #    dynamodb_table = "bcgov-ecf-billing-reports-tfrb-state-locks"
  #  }
}

provider "aws" {
  region = var.aws_region
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

resource "aws_s3_bucket" "athena_query_output_bucket" {
  bucket        = "bcgov-ecf-billing-reports-output-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  acl           = "private"
  force_destroy = false
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
    command = <<-EOT
      export DOCKER_BUILDKIT=0
      export COMPOSE_DOCKER_CLI_BUILD=0
      aws ecr get-login-password --region ${data.aws_region.current.name} | docker login \
        --username AWS \
        --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
      docker build -t ${local.app_name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name} -f ../Dockerfile ../
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
        "Sid" : "PermissionsToAssumeAthenaCostRoleOnMasterAccount",
        "Effect" : "Allow",
        "Action" : "sts:AssumeRole",
        "Resource" : "arn:aws:iam::${var.lz_master_account_id}:role/BCGov-Athena-Cost-and-Usage-Report"
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
}

resource "aws_ecs_task_definition" "billing_reports_ecs_task" {
  family                   = "${local.app_name}-ecs-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  container_definitions = jsonencode([{
    name       = "${local.app_name}-ecs-container-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
    image      = "${aws_ecr_repository.billing_reports_ecr.repository_url}:latest"
    entryPoint = ["python3", "billing-cpf-1068.py"]
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


## Mostly used for testing
#
resource "aws_cloudwatch_event_rule" "billing_reports_fiver_rule" {
  name                = "${local.app_name}-fiver-rule"
  description         = "Execute the ${local.app_name} every five minutes"
  schedule_expression = "rate(3 minutes)"
}

resource "aws_cloudwatch_event_target" "billing_reports_fiver_target" {
  target_id = "${local.app_name}-fiver-targer"
  arn       = aws_ecs_cluster.billing_reports_ecs_cluster.arn
  role_arn  = aws_iam_role.ecs_event_bridge_role.arn
  rule      = aws_cloudwatch_event_rule.billing_reports_fiver_rule.name

  input = jsonencode({
    containerOverrides = [{
      name = "${local.app_name}-ecs-container-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
      "environment" = [
        {
          "name"  = "REPORT_TYPE",
          "value" = "Weekly"
        },
        {
          "name"  = "DELIVER",
          "value" = "False"
        },
        {
          "name"  = "RECIPIENT_OVERRIDE",
          "value" = "hello.123h@hello.123.domain"
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET",
          "value" = aws_s3_bucket.athena_query_output_bucket.id
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET_ARN",
          "value" = aws_s3_bucket.athena_query_output_bucket.arn
        },
        {
          "name" = "ATHENA_QUERY_ROLE_TO_ASSUME_ARN",
          "value" = "arn:aws:iam::${var.lz_master_account_id}:role/BCGov-Athena-Cost-and-Usage-Report",
        },
        {
          "name" = "ATHENA_QUERY_DATABASE",
          "value" = "athenacurcfn_cost_and_usage_report",
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

resource "aws_cloudwatch_event_rule" "billing_reports_weekly_rule" {
  name                = "${local.app_name}-weekly-rule"
  description         = "Execute the ${local.app_name} every Friday at noon" // Note: 1900 UTC is 1200 PST
  schedule_expression = "cron(35 00 * * ? *)"
#  schedule_expression = "cron(0 19 ? * FRI *)"
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
          "name"  = "DELIVER",
          "value" = "False"
        },
        {
          "name"  = "RECIPIENT_OVERRIDE",
          "value" = "hello.123h@hello.123.domain"
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET",
          "value" = aws_s3_bucket.athena_query_output_bucket.id
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET_ARN",
          "value" = aws_s3_bucket.athena_query_output_bucket.arn
        },
        {
          "name" = "ATHENA_QUERY_ROLE_TO_ASSUME_ARN",
          "value" = "arn:aws:iam::${var.lz_master_account_id}:role/BCGov-Athena-Cost-and-Usage-Report",
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
  description         = "Execute the ${local.app_name} at noon on the last day every month" // Note: 1900 UTC is 1200 PST
  schedule_expression = "cron(37 00 * * ? *)"
#  schedule_expression = "cron(0 19 L * ? *)"
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
          "name"  = "DELIVER",
          "value" = "False"
        },
        {
          "name"  = "RECIPIENT_OVERRIDE",
          "value" = "hello.123h@hello.123.domain"
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET",
          "value" = aws_s3_bucket.athena_query_output_bucket.id
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET_ARN",
          "value" = aws_s3_bucket.athena_query_output_bucket.arn
        },
        {
          "name" = "ATHENA_QUERY_ROLE_TO_ASSUME_ARN",
          "value" = "arn:aws:iam::${var.lz_master_account_id}:role/BCGov-Athena-Cost-and-Usage-Report",
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
  schedule_expression = "cron(40 00 * * ? *)"
#  schedule_expression = "cron(0 19 L * ? *)"
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
          "name"  = "DELIVER",
          "value" = "False"
        },
        {
          "name"  = "RECIPIENT_OVERRIDE",
          "value" = "hello.123h@hello.123.domain"
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET",
          "value" = aws_s3_bucket.athena_query_output_bucket.id
        },
        {
          "name"  = "ATHENA_QUERY_OUTPUT_BUCKET_ARN",
          "value" = aws_s3_bucket.athena_query_output_bucket.arn
        },
        {
          "name" = "ATHENA_QUERY_ROLE_TO_ASSUME_ARN",
          "value" = "arn:aws:iam::${var.lz_master_account_id}:role/BCGov-Athena-Cost-and-Usage-Report",
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