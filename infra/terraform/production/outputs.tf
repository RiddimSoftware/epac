output "production_api_url" {
  description = "Production API custom domain base URL"
  value       = "https://${var.production_domain}"
}

output "execute_api_url" {
  description = "Production API Gateway execute-api base URL"
  value       = aws_apigatewayv2_api.production.api_endpoint
}

output "lambda_function_names" {
  description = "All production Lambda function names"
  value       = [for fn in aws_lambda_function.production : fn.function_name]
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for the production domain"
  value       = aws_acm_certificate.production_api.arn
}
