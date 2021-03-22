resource "aws_sfn_state_machine" "process_cur_sfn_state_machine" {
  name     = "process-cur-workflow"
  role_arn = aws_iam_role.sfn_exec_role.arn

  definition = <<EOF
{
  "Comment": "State Machine to process custom billing reporting",
  "StartAt": "ExecuteAthenaQuery",
  "States": {
    "ExecuteAthenaQuery": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.process_cur.arn}",
      "ResultPath": "$.local_file",
      "Next": "GenerateBusinessUnitReport"
    },
    "GenerateBusinessUnitReport": {
      "Type": "Map",
      "ItemsPath": "$.teams",
      "ResultPath": null,
      "Parameters": {
        "team.$": "$$.Map.Item.Value",
        "month.$": "$.month",
        "year.$": "$.year",
        "local_file.$": "$.local_file"
      },
      "Iterator": {
        "StartAt": "GenerateReport",
        "States": {
          "GenerateReport": {
            "Type": "Task",
            "Resource": "${aws_lambda_function.process_cur_reports.arn}",
            "End": true
          }
        }
      },
      "Next": "Cleanup"
    },
    "Cleanup": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.process_cur_cleanup.arn}",      
      "End": true
    }
  }
}
EOF
}


resource "aws_iam_role" "sfn_exec_role" {
  name               = "process-cur-sfn-role"
  assume_role_policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
     {
       "Action": "sts:AssumeRole",
       "Principal": {
         "Service": "states.amazonaws.com"
       },
       "Effect": "Allow"
     }
   ]
 }
 EOF

 tags = local.common_tags
}

data "aws_iam_policy" "SFNLambdaBasicExecutionPermissions" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
}

resource "aws_iam_role_policy_attachment" "sfn-basic-role-attach" {
  role       = aws_iam_role.sfn_exec_role.name
  policy_arn = data.aws_iam_policy.SFNLambdaBasicExecutionPermissions.arn
}
