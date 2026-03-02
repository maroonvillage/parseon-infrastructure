# Bootstrap root module
#
# Run this ONCE from your local machine to create the IAM group and policy
# that your Terraform operator user belongs to. Terraform Cloud (HCP Terraform)
# manages all remote state, so no S3 bucket or DynamoDB table is needed.
#
# Prerequisites (manual, one-time steps):
#   a) Create an IAM user in the AWS console (or reuse your existing one).
#      Temporarily attach "AdministratorAccess" just for this bootstrap run.
#   b) Configure your local AWS CLI:
#        aws configure --profile parseon-bootstrap
#   c) Run:
#        cd bootstrap/
#        terraform init
#        terraform apply -var="existing_user_name=<your-iam-username>"
#   d) Once apply succeeds, detach AdministratorAccess from the user.
#      The user now holds only the scoped group policy.
#   e) Create an access key for the user, then add it as environment variables
#      in Terraform Cloud (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) so that
#      the cloud workspaces can authenticate to AWS.
#
# NOTE: This module uses LOCAL state intentionally — it bootstraps IAM before
# Terraform Cloud workspaces are authorised. Add bootstrap/terraform.tfstate
# to .gitignore and store it safely (e.g. encrypted S3, 1Password).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state is intentional — do NOT add a cloud or backend block here.
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# ── IAM Group + Policy + User membership ──────────────────────────────────────
module "terraform_iam" {
  source = "../modules/terraform_iam"

  group_name         = var.iam_group_name
  create_user        = var.create_terraform_user
  user_name          = var.terraform_user_name
  existing_user_name = var.existing_user_name
}
