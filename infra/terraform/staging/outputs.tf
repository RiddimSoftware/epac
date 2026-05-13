output "staging_api_url" {
  description = "Staging API base URL"
  value       = "https://${var.staging_domain}"
}

output "lambda_function_names" {
  description = "All staging Lambda function names"
  value       = [for fn in aws_lambda_function.staging : fn.function_name]
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for the staging domain (already issued)"
  value       = aws_acm_certificate.staging_api.arn
}
