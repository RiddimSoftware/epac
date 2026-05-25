locals {
  manifest = jsondecode(file("${path.module}/../../../backend/manifest/deployment-services.json"))

  services = [
    for svc in local.manifest.services : svc.name
    if try(svc.deploy.staging, false)
  ]

  account_id = "227530433709"

  # HTTP-capable services mapped to the Lambda payload format version.
  # daily-fetch uses WrapNoEvent (scheduled job) and loader is a CLI tool.
  # Both are deploy-only and excluded from API Gateway wiring.
  http_services = {
    for svc in local.manifest.services : svc.name => svc.http.payload_format_version
    if try(svc.http != null, false) && try(svc.deploy.staging, false)
  }

  staging_api_routes = flatten([
    for svc in local.manifest.services : [
      for route in try(svc.http.routes.staging, []) : {
        service   = svc.name
        route_key = "${route.method} ${route.path}"
      }
    ] if try(svc.http != null, false) && try(svc.deploy.staging, false)
  ])

  staging_api_routes_by_key = {
    for route in local.staging_api_routes :
    "${route.service}::${route.route_key}" => route
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
    # environment: managed by the deploy workflow.
    ignore_changes = [filename, source_code_hash, environment]
  }

  tags = {
    Project        = "epac"
    Environment    = "staging"
    ManagedBy      = "terraform"
    Ticket         = "EPAC-1852"
    LastReviewedAt = "2026-05-25"
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
    Ticket      = "EPAC-1852"
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

# Routes — derived from the backend manifest.
resource "aws_apigatewayv2_route" "staging" {
  for_each = local.staging_api_routes_by_key

  api_id    = var.apigw_api_id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.staging[each.value.service].id}"
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
