#!/bin/bash

set -e

IMAGE_NAME=worker-test
AWS_REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

ECR_URL="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

REPO_NAME=worker-repo

echo "Account: $ACCOUNT_ID"
echo "Region:  $AWS_REGION"
echo "Repo:    $REPO_NAME"
echo "ECR URL: $ECR_URL"

# create repo if not exists
#aws ecr describe-repositories --repository-names $REPO_NAME >/dev/null 2>&1 || \
#aws ecr create-repository --repository-name $REPO_NAME


# Ensure repo exists
if ! aws ecr describe-repositories \
    --repository-names "$REPO_NAME" \
    --region "$AWS_REGION" >/dev/null 2>&1; then

  echo "Creating ECR repository..."
  aws ecr create-repository \
    --repository-name "$REPO_NAME" \
    --region "$AWS_REGION" >/dev/null
fi


# login
aws ecr get-login-password --region $AWS_REGION | \
docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# build
docker build -t $IMAGE_NAME ./services/worker

# tag
docker tag $IMAGE_NAME:latest \
$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest

# push
docker push \
$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest

echo "✅ Worker image pushed"