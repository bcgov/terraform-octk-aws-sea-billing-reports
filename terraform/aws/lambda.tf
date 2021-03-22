resource "aws_lambda_function" "process_cur" {
  function_name = "SEA-Process-CURs"
  filename      = "lambda/dist/lambda_process_cur.zip"

  source_code_hash = filebase64sha256("lambda/dist/lambda_process_cur.zip")

  handler = "index.handler"
  runtime = "python3.8"
  layers  = ["${aws_lambda_layer_version.python38-process-cur-layer.arn}"]

  timeout          = 600
  memory_size      = 2048

  role = aws_iam_role.lambda_exec.arn

  # file_system_config {
  #     arn = aws_efs_access_point.access_point_for_lambda.arn
  #     local_mount_path = "/mnt/efs"
  # }
  
  # vpc_config {
  #   # Every subnet should be able to reach an EFS mount target in the same Availability Zone. Cross-AZ mounts are not permitted.
  #   subnet_ids         = [aws_subnet.private_vpc_subnet_a.id, aws_subnet.private_vpc_subnet_b.id]
  #   security_group_ids = [aws_security_group.allow_efs.id]
  # }

  # depends_on = [aws_efs_access_point.access_point_for_lambda]
   environment {
    variables = {
      ATHENA_DATABASE = var.athena_database
      S3_BUCKET = aws_s3_bucket.billing_reports.id
    }
  }

  tags = local.common_tags

  
}


resource "aws_lambda_function" "process_cur_reports" {
  function_name = "SEA-Process-CUR-Report"
  filename      = "lambda/dist/lambda_process_cur_reports.zip"

  source_code_hash = filebase64sha256("lambda/dist/lambda_process_cur_reports.zip")

  handler = "index.handler"
  runtime = "python3.8"
  layers  = ["${aws_lambda_layer_version.python38-process-cur-layer.arn}"]

  timeout          = 600
  memory_size      = 2048

  role = aws_iam_role.lambda_exec.arn
  # file_system_config {
  #     arn = aws_efs_access_point.access_point_for_lambda.arn
  #     local_mount_path = "/mnt/efs"
  # }  
  # vpc_config {
  #   # Every subnet should be able to reach an EFS mount target in the same Availability Zone. Cross-AZ mounts are not permitted.
  #   subnet_ids         = [aws_subnet.private_vpc_subnet_a.id, aws_subnet.private_vpc_subnet_b.id]
  #   security_group_ids = [aws_security_group.allow_efs.id]
  # }

  # depends_on = [aws_efs_access_point.access_point_for_lambda]
   environment {
    variables = {    
      S3_BUCKET = aws_s3_bucket.billing_reports.id
    }
  }

  tags = local.common_tags


}



resource "aws_lambda_function" "process_cur_cleanup" {
  function_name = "SEA-Process-CUR-Cleanup"
  filename      = "lambda/dist/lambda_process_cur_cleanup.zip"

  source_code_hash = filebase64sha256("lambda/dist/lambda_process_cur_cleanup.zip")

  handler = "index.handler"
  runtime = "python3.8"
  layers  = ["${aws_lambda_layer_version.python38-process-cur-layer.arn}"]

  timeout          = 600
  memory_size      = 512

   role = aws_iam_role.lambda_exec.arn

#   file_system_config {
#       arn = aws_efs_access_point.access_point_for_lambda.arn
#       local_mount_path = "/mnt/efs"
#   }
#    vpc_config {
#     # Every subnet should be able to reach an EFS mount target in the same Availability Zone. Cross-AZ mounts are not permitted.
#     subnet_ids         = [aws_subnet.private_vpc_subnet_a.id, aws_subnet.private_vpc_subnet_b.id]
#     security_group_ids = [aws_security_group.allow_efs.id]
#   }

#  depends_on = [aws_efs_access_point.access_point_for_lambda]
   environment {
    variables = {    
      S3_BUCKET = aws_s3_bucket.billing_reports.id
    }
  }

  tags = local.common_tags

 
}


resource "aws_lambda_layer_version" "python38-process-cur-layer" {
  filename            = "lambda/dist/python3-layers.zip"
  layer_name          = "python3-cur"
  source_code_hash    = filebase64sha256("lambda/dist/python3-layers.zip")
  compatible_runtimes = ["python3.8"]
}

resource "aws_iam_role" "lambda_exec" {
  name               = "process-cur-lambda-role"
  assume_role_policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
     {
       "Action": "sts:AssumeRole",
       "Principal": {
         "Service": "lambda.amazonaws.com"
       },
       "Effect": "Allow"
     }
   ]
 }
 EOF

 tags = local.common_tags
}


data "aws_iam_policy" "AWSLambdaBasicExecutionRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda-basic-role-attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn
}


resource "aws_iam_role_policy" "process_cur_permissions" {
  name = "process_cur_permissions"  
  role = aws_iam_role.lambda_exec.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
          "Effect": "Allow",
          "Action": [
              "athena:BatchGet*",
              "athena:Get*",
              "athena:List*",
              "athena:StartQueryExecution",
              "athena:StopQueryExecution",
              "glue:GetTable",
              "glue:GetPartitions",
              "glue:GetPartition"
          ],
          "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads",
                "s3:ListMultipartUploadParts",
                "s3:AbortMultipartUpload"
            ],
            "Resource": [
                "${aws_s3_bucket.billing_reports.arn}",
                "${aws_s3_bucket.billing_reports.arn}/*",
                "${var.athena_queries_bucket_arn}",
                "${var.athena_queries_bucket_arn}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [         
                "s3:GetObject",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [                
                "${var.billing_cur_bucket_arn}",
                "${var.billing_cur_bucket_arn}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [         
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:GenerateDataKey"
            ],
            "Resource": [                
                "${var.kms_master_key_id}"
            ]
        }
    ]
  }
  EOF  
}