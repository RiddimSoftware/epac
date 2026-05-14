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

  # HTTP-capable services mapped to the Lambda event shape their handlers accept.
  # daily-fetch uses WrapNoEvent (scheduled job) and loader is a CLI tool.
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

# Production HTTP API (existing API ID smun5g2szc; import before apply).
resource "aws_apigatewayv2_api" "production" {
  name          = "epac-api-api"
  protocol_type = "HTTP"

  tags = {
    Project     = "epac"
    Environment = "production"
  }
}

# Existing production stage. Auto-deploy stays false to preserve current release gating.
resource "aws_apigatewayv2_stage" "production" {
  api_id      = aws_apigatewayv2_api.production.id
  name        = "production"
  auto_deploy = false

  default_route_settings {
    detailed_metrics_enabled = false
    throttling_burst_limit   = 50
    throttling_rate_limit    = 20
  }
}

# Lambda functions: search, member-speeches, and daily-fetch are existing imports.
# The remaining production functions are created from a placeholder zip, with code
# and environment managed later by the production backend deployment workflow.
resource "aws_lambda_function" "production" {
  for_each = toset(local.services)

  function_name = each.key
  role          = var.lambda_role_arn
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  handler       = "bootstrap"
  publish       = false

  filename = "${path.module}/placeholder.zip"

  lifecycle {
    # filename/source_code_hash: managed by the backend deploy workflow.
    # environment: DATABASE_URL and service secrets are injected outside Terraform.
    ignore_changes = [filename, source_code_hash, environment]
  }
}

# ACM certificate for the production custom domain (already issued; imported into state).
resource "aws_acm_certificate" "production_api" {
  domain_name       = var.production_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Route53 CNAME record for ACM DNS validation.
# Values are static (set when the cert was issued) so Terraform can plan without apply-time unknowns.
resource "aws_route53_record" "acm_validation" {
  zone_id = var.route53_zone_id
  name    = "_829ab5a6bd19a6588d86c3f682836534.api.epac.riddimsoftware.com"
  type    = "CNAME"
  ttl     = 300
  records = ["_22cf5e3488c849a7d38770683b3455c4.jkddzztszm.acm-validations.aws."]
}

# API Gateway v2 custom domain for production.
resource "aws_apigatewayv2_domain_name" "production" {
  domain_name = var.production_domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.production_api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

# Map the production stage of epac-api-api to the custom domain.
resource "aws_apigatewayv2_api_mapping" "production" {
  api_id      = aws_apigatewayv2_api.production.id
  domain_name = aws_apigatewayv2_domain_name.production.id
  stage       = aws_apigatewayv2_stage.production.name
}

# Route53 alias A record pointing at the API Gateway regional domain.
resource "aws_route53_record" "production_api" {
  zone_id = var.route53_zone_id
  name    = var.production_domain
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.production.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.production.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# API Gateway integrations — one per HTTP-capable production Lambda.
resource "aws_apigatewayv2_integration" "production" {
  for_each = local.http_services

  api_id                 = aws_apigatewayv2_api.production.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.production[each.key].arn
  payload_format_version = each.value
  timeout_milliseconds   = 30000
}

# Routes — compatibility routes cover current iOS clients and documented /api/v1 paths.
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.production["health"].id}"
}

resource "aws_apigatewayv2_route" "search_legacy" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "ANY /search"
  target    = "integrations/${aws_apigatewayv2_integration.production["search"].id}"
}

resource "aws_apigatewayv2_route" "search_speeches" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /search/speeches"
  target    = "integrations/${aws_apigatewayv2_integration.production["search"].id}"
}

resource "aws_apigatewayv2_route" "member_speeches_legacy" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /members/{memberId}/speeches"
  target    = "integrations/${aws_apigatewayv2_integration.production["member-speeches"].id}"
}

resource "aws_apigatewayv2_route" "member_speeches" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /api/v1/members/{id}/speeches"
  target    = "integrations/${aws_apigatewayv2_integration.production["member-speeches"].id}"
}

resource "aws_apigatewayv2_route" "on_this_day" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /api/v1/on-this-day"
  target    = "integrations/${aws_apigatewayv2_integration.production["on-this-day"].id}"
}

resource "aws_apigatewayv2_route" "riding_boundary" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /api/v1/ridings/{slug}/boundary"
  target    = "integrations/${aws_apigatewayv2_integration.production["riding-boundary"].id}"
}

resource "aws_apigatewayv2_route" "live_status" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /api/v1/live"
  target    = "integrations/${aws_apigatewayv2_integration.production["live-status"].id}"
}

resource "aws_apigatewayv2_route" "house_calendar_legacy" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /calendar/house.ics"
  target    = "integrations/${aws_apigatewayv2_integration.production["live-status"].id}"
}

resource "aws_apigatewayv2_route" "house_calendar" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /api/v1/calendar/house.ics"
  target    = "integrations/${aws_apigatewayv2_integration.production["live-status"].id}"
}

resource "aws_apigatewayv2_route" "device_register_legacy" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "POST /device/register"
  target    = "integrations/${aws_apigatewayv2_integration.production["device-register"].id}"
}

resource "aws_apigatewayv2_route" "device_register" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "POST /api/v1/device/register"
  target    = "integrations/${aws_apigatewayv2_integration.production["device-register"].id}"
}

resource "aws_apigatewayv2_route" "openapi_json" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /openapi.json"
  target    = "integrations/${aws_apigatewayv2_integration.production["openapi"].id}"
}

resource "aws_apigatewayv2_route" "openapi_docs" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /docs"
  target    = "integrations/${aws_apigatewayv2_integration.production["openapi"].id}"
}

resource "aws_apigatewayv2_route" "openapi_json_v1" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /api/v1/openapi.json"
  target    = "integrations/${aws_apigatewayv2_integration.production["openapi"].id}"
}

resource "aws_apigatewayv2_route" "openapi_docs_v1" {
  api_id    = aws_apigatewayv2_api.production.id
  route_key = "GET /api/v1/docs"
  target    = "integrations/${aws_apigatewayv2_integration.production["openapi"].id}"
}

# Lambda invoke permissions — one per HTTP-capable Lambda, scoped to the production API.
resource "aws_lambda_permission" "production_apigw" {
  for_each = local.http_services

  statement_id  = "apigw-production-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.production[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${local.account_id}:${aws_apigatewayv2_api.production.id}/*/*"
}
