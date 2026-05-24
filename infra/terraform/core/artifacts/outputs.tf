output "bucket_arn" {
  description = "ARN of the epac artifacts bucket."
  value       = aws_s3_bucket.artifacts.arn
}

output "bucket_name" {
  description = "Name of the epac artifacts bucket."
  value       = aws_s3_bucket.artifacts.id
}

output "distribution_id" {
  description = "CloudFront distribution ID for artifact reads."
  value       = aws_cloudfront_distribution.artifacts.id
}

output "distribution_domain_name" {
  description = "CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.artifacts.domain_name
}

output "custom_domain_name" {
  description = "Custom domain name routed to CloudFront."
  value       = var.custom_domain_name
}
