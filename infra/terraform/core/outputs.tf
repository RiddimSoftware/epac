output "terraform_state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "terraform_locks_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}

output "artifacts_bucket_arn" {
  description = "ARN of the epac artifacts bucket."
  value       = module.artifacts.bucket_arn
}

output "artifacts_bucket_name" {
  description = "Name of the epac artifacts bucket."
  value       = module.artifacts.bucket_name
}

output "artifacts_distribution_id" {
  description = "CloudFront distribution ID for artifact reads."
  value       = module.artifacts.distribution_id
}

output "artifacts_distribution_domain_name" {
  description = "CloudFront distribution domain name."
  value       = module.artifacts.distribution_domain_name
}

output "artifacts_custom_domain_name" {
  description = "Custom domain name routed to CloudFront."
  value       = module.artifacts.custom_domain_name
}
