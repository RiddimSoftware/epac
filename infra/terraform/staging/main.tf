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

  # Placeholder zip — CI overwrites code on every staging deploy.
  filename = "${path.module}/placeholder.zip"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# ACM certificate for the staging custom domain (already issued; imported into state).
resource "aws_acm_certificate" "staging_api" {
  domain_name       = var.staging_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
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
