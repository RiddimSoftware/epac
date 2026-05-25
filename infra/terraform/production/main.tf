locals {
  manifest = jsondecode(file("${path.module}/../../../backend/manifest/deployment-services.json"))

  services = [
    for svc in local.manifest.services : svc.name
    if try(svc.deploy.production, false)
  ]

  account_id = "227530433709"

  # HTTP-capable services mapped to the Lambda event shape their handlers accept.
  # daily-fetch uses WrapNoEvent (scheduled job) and loader is a CLI tool.
  http_services = {
    for svc in local.manifest.services : svc.name => svc.http.payload_format_version
    if try(svc.http != null, false) && try(svc.deploy.production, false)
  }

  production_api_routes = flatten([
    for svc in local.manifest.services : [
      for route in try(svc.http.routes.production, []) : {
        service   = svc.name
        route_key = "${route.method} ${route.path}"
      }
    ] if try(svc.http != null, false) && try(svc.deploy.production, false)
  ])

  production_api_routes_by_key = {
    for route in local.production_api_routes :
    "${route.service}::${route.route_key}" => route
  }

  # Existing Lambda policies contain apigw-production-* statements for
  # an older API. Use a distinct Sid prefix for this API to avoid
  # AddPermission conflicts when Terraform creates the production invoke permissions.
  api_permission_statement_ids = {
    for service in keys(local.http_services) :
    service => "apigw-epac-api-${service}"
  }

  canonical_function_services = toset([
    "hansard-search-index",
  ])

  lambda_config = {
    "hansard-search-index" = {
      timeout     = 900
      memory_size = 1024
    }
  }
}

# Production HTTP API (existing API ID smun5g2szc; import before apply).
resource "aws_apigatewayv2_api" "production" {
  name          = "epac-api-api"
  protocol_type = "HTTP"

  tags = {
    Project        = "epac"
    Environment    = "production"
    ManagedBy      = "terraform"
    Ticket         = "EPAC-1852"
    LastReviewedAt = "2026-05-25"
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

  tags = {
    Project     = "epac"
    Environment = "production"
    ManagedBy   = "terraform"
    Ticket      = "EPAC-1852"
  }
}

# Lambda functions: search, member-speeches, and daily-fetch are existing imports.
# The remaining production functions are created from a placeholder zip, with code
# and environment managed later by the production backend deployment workflow.
resource "aws_lambda_function" "production" {
  for_each = toset(local.services)

  function_name = contains(local.canonical_function_services, each.key) ? "epac-${each.key}-production" : each.key
  role          = var.lambda_role_arn
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  handler       = "bootstrap"
  publish       = false
  timeout       = try(local.lambda_config[each.key].timeout, null)
  memory_size   = try(local.lambda_config[each.key].memory_size, null)

  filename = "${path.module}/placeholder.zip"

  lifecycle {
    # filename/source_code_hash: managed by the backend deploy workflow.
    # environment: managed by the deploy workflow.
    ignore_changes = [filename, source_code_hash, environment]
  }

  tags = {
    Project     = "epac"
    Environment = "production"
    ManagedBy   = "terraform"
    Ticket      = "EPAC-1852"
  }
}

# ACM certificate for the production domain (already issued; imported into state).
resource "aws_acm_certificate" "production_api" {
  domain_name       = var.production_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project     = "epac"
    Environment = "production"
    ManagedBy   = "terraform"
    Ticket      = "EPAC-1852"
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

# Routes — derived from the backend manifest.
resource "aws_apigatewayv2_route" "production" {
  for_each = local.production_api_routes_by_key

  api_id    = aws_apigatewayv2_api.production.id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.production[each.value.service].id}"
}

# Lambda invoke permissions — one per HTTP-capable Lambda, scoped to the production API.
resource "aws_lambda_permission" "production_apigw" {
  for_each = local.http_services

  statement_id  = local.api_permission_statement_ids[each.key]
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.production[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${local.account_id}:${aws_apigatewayv2_api.production.id}/*/*"
}
