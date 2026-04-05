# IAM Module
data "aws_iam_policy_document" "ecs_task_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "ecs_execution_role" {
  name               = "${var.name_prefix}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
}
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Inline policy granting the execution role access to pull secrets/parameters
# at task launch (the `secrets:` block in container definitions).
# The managed AmazonECSTaskExecutionRolePolicy does NOT include these.
data "aws_iam_policy_document" "secrets_injection" {
  count = (length(var.secrets_arns) + length(var.ssm_parameter_arns)) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = length(var.secrets_arns) > 0 ? [1] : []
    content {
      sid    = "SecretsManagerRead"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = var.secrets_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.ssm_parameter_arns) > 0 ? [1] : []
    content {
      sid    = "SSMParameterRead"
      effect = "Allow"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      resources = var.ssm_parameter_arns
    }
  }
}

resource "aws_iam_role_policy" "secrets_injection" {
  count  = (length(var.secrets_arns) + length(var.ssm_parameter_arns)) > 0 ? 1 : 0
  name   = "${var.name_prefix}-secrets-injection"
  role   = aws_iam_role.ecs_execution_role.name
  policy = data.aws_iam_policy_document.secrets_injection[0].json
}
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
}
data "aws_iam_policy_document" "s3_access" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = flatten([
      for arn in var.s3_bucket_arns : [
        arn,
        "${arn}/*"
      ]
    ])
  }
}
data "aws_iam_policy_document" "sqs_access" {
  count = length(var.sqs_queue_arns) > 0 ? 1 : 0

  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]

    resources = var.sqs_queue_arns
  }
}
data "aws_iam_policy_document" "secrets_access" {
  count = length(var.secrets_arns) > 0 ? 1 : 0

  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = var.secrets_arns
  }
}
data "aws_iam_policy_document" "rds_iam_auth" {
  count = var.enable_rds_iam_auth ? 1 : 0

  statement {
    actions   = ["rds-db:connect"]
    resources = ["*"] # Note: In production you should scope this to specific DB resource IDs, not wildcard.
  }
}

data "aws_iam_policy_document" "combined_task_policy" {
  source_policy_documents = compact([
    length(var.s3_bucket_arns) > 0 ? data.aws_iam_policy_document.s3_access[0].json : null,
    length(var.sqs_queue_arns) > 0 ? data.aws_iam_policy_document.sqs_access[0].json : null,
    length(var.secrets_arns) > 0 ? data.aws_iam_policy_document.secrets_access[0].json : null,
    var.enable_rds_iam_auth ? data.aws_iam_policy_document.rds_iam_auth[0].json : null
  ])
}

resource "aws_iam_policy" "ecs_task_policy" {
  name   = "${var.name_prefix}-ecs-task-policy"
  policy = data.aws_iam_policy_document.combined_task_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}
