# GitHub Actions OIDC Module
#
# Creates an IAM OIDC identity provider for GitHub Actions and a scoped IAM
# role the CD pipeline can assume to push images to ECR and trigger ECS deploys.
# No long-lived credentials are stored — authentication is entirely token-based.

# ── OIDC Provider ─────────────────────────────────────────────────────────────
# Only one provider can exist per AWS account. Set create_oidc_provider=false
# if the provider already exists (e.g. created by another module or manually).

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's published OIDC thumbprints (both active as of 2024)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ── Trust Policy ──────────────────────────────────────────────────────────────
# Restricts assume-role to tokens issued for the specified GitHub repository.
# The :* suffix allows any branch/tag in that repo to assume the role —
# lock down further (e.g. ":ref:refs/heads/main") if desired.

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name_prefix}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = {
    Name = "${var.name_prefix}-github-actions-role"
  }
}

# ── Permissions Policy ────────────────────────────────────────────────────────

data "aws_iam_policy_document" "github_actions" {
  # ECR GetAuthorizationToken is not resource-scoped — AWS requires "*"
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR image push/pull scoped to the specific repository ARNs
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
    resources = var.ecr_repository_arns
  }

  # ECS — trigger a new deployment and wait for stability
  statement {
    sid    = "ECSDeploy"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = ["*"]
  }

  # Frontend — sync React build artifacts to the S3 frontend bucket
  dynamic "statement" {
    for_each = var.frontend_bucket_arn != null ? [1] : []
    content {
      sid    = "FrontendS3Sync"
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListBucket",
      ]
      resources = [
        var.frontend_bucket_arn,
        "${var.frontend_bucket_arn}/*",
      ]
    }
  }

  # Frontend — invalidate stale CloudFront cache after each deploy
  dynamic "statement" {
    for_each = var.cloudfront_distribution_arn != null ? [1] : []
    content {
      sid       = "CloudFrontInvalidate"
      effect    = "Allow"
      actions   = ["cloudfront:CreateInvalidation"]
      resources = [var.cloudfront_distribution_arn]
    }
  }
}

resource "aws_iam_policy" "github_actions" {
  name   = "${var.name_prefix}-github-actions-policy"
  policy = data.aws_iam_policy_document.github_actions.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}
