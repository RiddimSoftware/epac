locals {
  account_id            = "227530433709"
  hansard_search_prefix = trim(var.hansard_search_prefix, "/")

  backend_ci_roles = {
    staging    = "GitHubActions-epac-backend-staging"
    production = "GitHubActions-epac-backend-production"
  }

  artifact_bucket_arns = [
    module.artifacts.bucket_arn,
    "${module.artifacts.bucket_arn}/*",
    "${module.artifacts.bucket_arn}/hansard-search/*"
  ]

  terraform_workspaces = ["core", "staging", "production"]

  terraform_state_bucket_names = [
    for workspace in local.terraform_workspaces : "epac-tfstate-${workspace}-${local.account_id}"
  ]

  terraform_state_arns = flatten([
    for bucket in local.terraform_state_bucket_names : [
      "arn:aws:s3:::${bucket}",
      "arn:aws:s3:::${bucket}/*"
    ]
  ])

  terraform_lock_table_arns = [
    for workspace in local.terraform_workspaces : "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/epac-tfstate-lock-${workspace}"
  ]

  api_gateway_arns = [
    "arn:aws:apigateway:${var.aws_region}::/apis/f4x35gduxl",
    "arn:aws:apigateway:${var.aws_region}::/apis/f4x35gduxl/*",
    "arn:aws:apigateway:${var.aws_region}::/apis/bdnpz6v3c8",
    "arn:aws:apigateway:${var.aws_region}::/apis/bdnpz6v3c8/*"
  ]

  legacy_production_lambda_names = [
    "daily-fetch",
    "loader",
    "members",
    "sittings",
    "bills",
    "search",
    "member-speeches",
    "member-votes",
    "on-this-day",
    "estimates",
    "riding-boundary",
    "calendar",
    "config",
    "health",
    "device-register",
    "openapi",
    "live-status"
  ]

  production_lambda_arns = concat(
    ["arn:aws:lambda:${var.aws_region}:${local.account_id}:function:epac-*-production"],
    [for name in local.legacy_production_lambda_names : "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${name}"]
  )
}

data "aws_iam_policy_document" "backend_ci_common" {
  # API Gateway v2 resources use the apigateway IAM action namespace.
  statement {
    sid = "ManageExistingApis"
    actions = [
      "apigateway:*"
    ]
    resources = local.api_gateway_arns
  }

  statement {
    sid       = "ManageStateAndArtifacts"
    actions   = ["s3:*"]
    resources = concat(local.artifact_bucket_arns, local.terraform_state_arns)
  }

  statement {
    sid       = "UseTerraformStateLock"
    actions   = ["dynamodb:*"]
    resources = local.terraform_lock_table_arns
  }

  statement {
    sid       = "PassLambdaExecutionRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/epac-lambda-role"]
  }

  statement {
    sid       = "ManageEventBridgeSchedules"
    actions   = ["events:*"]
    resources = ["arn:aws:events:${var.aws_region}:${local.account_id}:rule/epac-*"]
  }

  statement {
    sid       = "ReadEpacSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:epac/*"]
  }

  statement {
    sid     = "ManageLambdaLogs"
    actions = ["logs:*"]
    resources = [
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/epac-*",
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/epac-*:*"
    ]
  }

  statement {
    sid       = "PublishMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }

  statement {
    sid       = "GetCallerIdentity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # Current Terraform state includes ACM certs and Route53 records for API domains.
  statement {
    sid = "ManageApiDomains"
    actions = [
      "acm:AddTagsToCertificate",
      "acm:DeleteCertificate",
      "acm:DescribeCertificate",
      "acm:ListTagsForCertificate",
      "acm:RequestCertificate",
      "acm:UpdateCertificateOptions",
      "route53:ChangeResourceRecordSets",
      "route53:GetChange",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "backend_staging_ci" {
  source_policy_documents = [data.aws_iam_policy_document.backend_ci_common.json]

  statement {
    sid       = "ManageStagingLambda"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:${var.aws_region}:${local.account_id}:function:epac-*-staging"]
  }
}

data "aws_iam_policy_document" "backend_production_ci" {
  source_policy_documents = [data.aws_iam_policy_document.backend_ci_common.json]

  statement {
    sid       = "ManageProductionLambda"
    actions   = ["lambda:*"]
    resources = local.production_lambda_arns
  }
}

resource "aws_iam_role_policy" "backend_staging_ci" {
  name   = "EpacStagingDeploy"
  role   = local.backend_ci_roles.staging
  policy = data.aws_iam_policy_document.backend_staging_ci.json
}

resource "aws_iam_role_policy" "backend_production_ci" {
  name   = "EpacProductionDeploy"
  role   = local.backend_ci_roles.production
  policy = data.aws_iam_policy_document.backend_production_ci.json
}

data "aws_iam_policy_document" "lambda_hansard_search_index_artifacts" {
  statement {
    sid    = "AllowHansardSearchIndexArtifactWrites"
    effect = "Allow"

    actions = [
      # AWS authorizes HeadObject through s3:GetObject; there is no separate
      # s3:HeadObject IAM action.
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "arn:aws:s3:::${var.artifacts_bucket_name}/${local.hansard_search_prefix}/*",
    ]
  }

  # hansard-search Lambda (EPAC-2063) needs ListBucket to enumerate index artifacts.
  statement {
    sid    = "AllowHansardSearchIndexArtifactList"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.hansard_search_prefix}/*"]
    }
  }
}

resource "aws_iam_role_policy" "lambda_hansard_search_index_artifacts" {
  name   = "epac-hansard-search-index-artifacts"
  role   = var.lambda_role_name
  policy = data.aws_iam_policy_document.lambda_hansard_search_index_artifacts.json
}
