# terraform_iam Module
#
# This module is NOT called from the environment root modules.
# It is a one-time bootstrap resource meant to be applied separately
# (e.g. from a dedicated bootstrap/ directory) before any environment
# Terraform is ever run.
#
# It creates:
#   • An IAM group ("terraform-operators") with a scoped policy attached.
#   • The policy grants the minimum permissions required to run all modules
#     in this repository (VPC, ECS, ALB, RDS, S3, SQS, CloudFront, Secrets,
#     IAM role/policy management, CloudWatch, App Auto Scaling).
#   • An optional IAM user that is added to the group (set create_user=false
#     if you already have a user and just want to move it into the group).
#
# SECURITY NOTE: IAM policy actions here are scoped to actions actually
# needed by the Terraform modules. Wildcard resource scope (*) is used only
# where AWS does not support resource-level permissions for that action.
# Tighten resource ARNs further once your account ID and naming conventions
# are stable.

# ── Group ──────────────────────────────────────────────────────────────────────
resource "aws_iam_group" "terraform_operators" {
  name = var.group_name
  path = "/terraform/"
}

# ── Policy document ────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "terraform_permissions" {
  # ---------- EC2 / VPC / Networking ----------
  statement {
    sid    = "VPC"
    effect = "Allow"
    actions = [
      "ec2:*Vpc*",
      "ec2:*Subnet*",
      "ec2:*InternetGateway*",
      "ec2:*NatGateway*",
      "ec2:*RouteTable*",
      "ec2:*Route",
      "ec2:*SecurityGroup*",
      "ec2:*Address*",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeAccountAttributes",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  # ---------- ECS ----------
  statement {
    sid    = "ECS"
    effect = "Allow"
    actions = [
      "ecs:*Cluster*",
      "ecs:*Service*",
      "ecs:*TaskDefinition*",
      "ecs:*CapacityProvider*",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # ---------- ECR (needed to push images before ECS deploy) ----------
  statement {
    sid    = "ECR"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:TagResource",
    ]
    resources = ["*"]
  }

  # ---------- ALB / ELB ----------
  statement {
    sid    = "ELB"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:*",
    ]
    resources = ["*"]
  }

  # ---------- Application Auto Scaling ----------
  statement {
    sid    = "AutoScaling"
    effect = "Allow"
    actions = [
      "application-autoscaling:*",
    ]
    resources = ["*"]
  }

  # ---------- RDS ----------
  statement {
    sid    = "RDS"
    effect = "Allow"
    actions = [
      "rds:*",
    ]
    resources = ["*"]
  }

  # ---------- S3 (app bucket + state bucket) ----------
  statement {
    sid    = "S3"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
    ]
    resources = ["*"]
  }

  # ---------- SQS ----------
  statement {
    sid    = "SQS"
    effect = "Allow"
    actions = [
      "sqs:*",
    ]
    resources = ["*"]
  }

  # ---------- CloudFront ----------
  statement {
    sid    = "CloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:*",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
    ]
    resources = ["*"]
  }

  # ---------- CloudWatch Logs ----------
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # ---------- IAM (scoped to role/policy management only — no user admin) ----------
  statement {
    sid    = "IAMRolesAndPolicies"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["*"]
  }

  # ---------- Secrets Manager (ARNs passed to ECS task role) ----------
  statement {
    sid    = "SecretsManager"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecrets",
      "secretsmanager:PutSecretValue",
      "secretsmanager:TagResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_permissions" {
  name        = "${var.group_name}-policy"
  description = "Minimum permissions for running Terraform against the Parseon infrastructure modules"
  policy      = data.aws_iam_policy_document.terraform_permissions.json
}

resource "aws_iam_group_policy_attachment" "terraform_permissions" {
  group      = aws_iam_group.terraform_operators.name
  policy_arn = aws_iam_policy.terraform_permissions.arn
}

# ── Optional: create the operator user and add to group ───────────────────────
resource "aws_iam_user" "terraform_operator" {
  count = var.create_user ? 1 : 0

  name = var.user_name
  path = "/terraform/"

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_user_group_membership" "terraform_operator" {
  count = var.create_user ? 1 : 0

  user   = aws_iam_user.terraform_operator[0].name
  groups = [aws_iam_group.terraform_operators.name]
}

# If you have an EXISTING user (create_user = false) set existing_user_name
# to add that user to the group instead.
resource "aws_iam_user_group_membership" "existing_operator" {
  count = var.create_user ? 0 : (var.existing_user_name != "" ? 1 : 0)

  user   = var.existing_user_name
  groups = [aws_iam_group.terraform_operators.name]
}
