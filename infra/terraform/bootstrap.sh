#!/usr/bin/env bash
#
# Bootstrap Terraform remote state storage for epac.
#
# Required environment:
# - AWS credentials for the target account, supplied by the standard AWS
#   credential chain. AWS_PROFILE is optional for local use.
# - The script always targets us-east-1; no AWS_REGION override is required.
#
# Required IAM permissions:
# - s3:CreateBucket
# - s3:PutBucketVersioning
# - s3:PutBucketEncryption
# - s3:PutBucketPublicAccessBlock
# - s3:HeadBucket
# - dynamodb:CreateTable
# - dynamodb:DescribeTable
# - sts:GetCallerIdentity
#
# Usage:
#   ./bootstrap.sh staging
#   ./bootstrap.sh production
set -euo pipefail

readonly REGION="us-east-1"

usage() {
  printf 'Usage: %s ENVIRONMENT\n\nENVIRONMENT must be staging or production.\n' "$0" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

readonly ENVIRONMENT="$1"

case "$ENVIRONMENT" in
  staging | production)
    ;;
  *)
    usage
    exit 2
    ;;
esac

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --region "$REGION")"
readonly ACCOUNT_ID

ensure_bucket() {
  local workspace="$1"
  local bucket="epac-tfstate-${workspace}-${ACCOUNT_ID}"

  if aws s3api head-bucket --bucket "$bucket" --region "$REGION" >/dev/null 2>&1; then
    printf '[%s] bucket exists, no-op: %s\n' "$workspace" "$bucket"
    return 0
  fi

  printf '[%s] creating bucket: %s\n' "$workspace" "$bucket"
  aws s3api create-bucket --bucket "$bucket" --region "$REGION" >/dev/null
  aws s3api put-bucket-versioning \
    --bucket "$bucket" \
    --versioning-configuration Status=Enabled \
    --region "$REGION"
  aws s3api put-bucket-encryption \
    --bucket "$bucket" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    --region "$REGION"
  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
    --region "$REGION"
}

ensure_lock_table() {
  local workspace="$1"
  local table="epac-tfstate-lock-${workspace}"

  if aws dynamodb describe-table --table-name "$table" --region "$REGION" >/dev/null 2>&1; then
    printf '[%s] lock table exists, no-op: %s\n' "$workspace" "$table"
    return 0
  fi

  printf '[%s] creating lock table: %s\n' "$workspace" "$table"
  aws dynamodb create-table \
    --table-name "$table" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    >/dev/null
  aws dynamodb wait table-exists --table-name "$table" --region "$REGION"
}

# The core workspace hosts shared resources and has its own backend. Bootstrapping
# staging or production also ensures core can initialize from a fresh account.
for workspace in core "$ENVIRONMENT"; do
  ensure_bucket "$workspace"
  ensure_lock_table "$workspace"
done
