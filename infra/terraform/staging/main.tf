locals {
  services = [
    "daily-fetch",
    "loader",
    "search",
    "member-speeches",
    "on-this-day",
    "riding-boundary",
    "health",
    "device-register",
    "openapi",
    "live-status",
  ]

  account_id = "227530433709"

  # HTTP-capable services mapped to their Lambda payload format version.
  # daily-fetch uses WrapNoEvent (scheduled job) and loader is a CLI tool —
  # neither handles HTTP events, so they are excluded from API Gateway wiring.
  http_services = {
    "health"          = "2.0"
    "search"          = "1.0"
    "member-speeches" = "1.0"
    "on-this-day"     = "1.0"
    "riding-boundary" = "1.0"
    "live-status"     = "2.0"
    "device-register" = "1.0"
    "openapi"         = "2.0"
  }
}

# Lambda functions — code is managed by the staging deploy workflow, not Terraform.
# lifecycle.ignore_changes on filename prevents Terraform from overwriting CI-deployed code.
resource "aws_lambda_function" "staging" {
  for_each = toset(local.services)

  function_name = "epac-${each.key}-staging"
  role          = var.lambda_role_arn
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  handler       = "bootstrap"
  publish       = false

  # Placeholder zip — CI overwrites code on every staging deploy.
  filename = "${path.module}/placeholder.zip"

  lifecycle {
    # filename/source_code_hash: managed by the staging deploy workflow.
    # environment: DATABASE_URL is injected by the deploy workflow via Secrets Manager.
    ignore_changes = [filename, source_code_hash, environment]
  }

  tags = {
    Project     = "epac"
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}

# ACM certificate for the staging custom domain (already issued; imported into state).
resource "aws_acm_certificate" "staging_api" {
  domain_name       = var.staging_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project     = "epac"
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}

# Route53 CNAME record for ACM DNS validation.
# Values are static (set when the cert was issued) so Terraform can plan without apply-time unknowns.
resource "aws_route53_record" "acm_validation" {
  zone_id = var.route53_zone_id
  name    = "_a9d0b8dee4d369c091e53099fff1bed3.staging-api.epac.riddimsoftware.com"
  type    = "CNAME"
  ttl     = 300
  records = ["_72c66198954a9e1ac6bee2c2b09aa9e8.jkddzztszm.acm-validations.aws."]
}

# API Gateway v2 custom domain for staging.
# References the cert ARN directly — validation is already complete and
# aws_acm_certificate_validation doesn't support import.
resource "aws_apigatewayv2_domain_name" "staging" {
  domain_name = var.staging_domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.staging_api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

# Map the staging stage of epac-api-api to the custom domain.
resource "aws_apigatewayv2_api_mapping" "staging" {
  api_id      = var.apigw_api_id
  domain_name = aws_apigatewayv2_domain_name.staging.id
  stage       = "staging"
}

# Route53 alias A record pointing at the API Gateway regional domain.
resource "aws_route53_record" "staging_api" {
  zone_id = var.route53_zone_id
  name    = var.staging_domain
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.staging.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.staging.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# API Gateway integrations — one per HTTP-capable Lambda.
resource "aws_apigatewayv2_integration" "staging" {
  for_each = local.http_services

  api_id                 = var.apigw_api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.staging[each.key].arn
  payload_format_version = each.value
}

# Routes — derived from smoke test paths and service handler comments.
resource "aws_apigatewayv2_route" "health" {
  api_id    = var.apigw_api_id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.staging["health"].id}"
}

resource "aws_apigatewayv2_route" "search_speeches" {
  api_id    = var.apigw_api_id
  route_key = "GET /search/speeches"
  target    = "integrations/${aws_apigatewayv2_integration.staging["search"].id}"
}

resource "aws_apigatewayv2_route" "member_speeches" {
  api_id    = var.apigw_api_id
  route_key = "GET /api/v1/members/{id}/speeches"
  target    = "integrations/${aws_apigatewayv2_integration.staging["member-speeches"].id}"
}

resource "aws_apigatewayv2_route" "on_this_day" {
  api_id    = var.apigw_api_id
  route_key = "GET /api/v1/on-this-day"
  target    = "integrations/${aws_apigatewayv2_integration.staging["on-this-day"].id}"
}

resource "aws_apigatewayv2_route" "riding_boundary" {
  api_id    = var.apigw_api_id
  route_key = "GET /api/v1/ridings/{slug}/boundary"
  target    = "integrations/${aws_apigatewayv2_integration.staging["riding-boundary"].id}"
}

resource "aws_apigatewayv2_route" "live_status" {
  api_id    = var.apigw_api_id
  route_key = "GET /api/v1/live"
  target    = "integrations/${aws_apigatewayv2_integration.staging["live-status"].id}"
}

resource "aws_apigatewayv2_route" "device_register" {
  api_id    = var.apigw_api_id
  route_key = "POST /api/v1/device/register"
  target    = "integrations/${aws_apigatewayv2_integration.staging["device-register"].id}"
}

resource "aws_apigatewayv2_route" "openapi_json" {
  api_id    = var.apigw_api_id
  route_key = "GET /openapi.json"
  target    = "integrations/${aws_apigatewayv2_integration.staging["openapi"].id}"
}

resource "aws_apigatewayv2_route" "openapi_docs" {
  api_id    = var.apigw_api_id
  route_key = "GET /docs"
  target    = "integrations/${aws_apigatewayv2_integration.staging["openapi"].id}"
}

# Lambda invoke permissions — one per HTTP-capable Lambda, scoped to the staging API.
resource "aws_lambda_permission" "staging_apigw" {
  for_each = local.http_services

  statement_id  = "apigw-staging-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.staging[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${local.account_id}:${var.apigw_api_id}/*/*"
}
