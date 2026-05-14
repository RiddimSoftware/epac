variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "lambda_role_arn" {
  description = "IAM role ARN for Lambda execution (epac-lambda-role)"
  type        = string
  default     = "arn:aws:iam::227530433709:role/epac-lambda-role"
}

variable "apigw_api_id" {
  description = "API Gateway v2 API ID (epac-api-staging — dedicated staging API)"
  type        = string
  default     = "f4x35gduxl"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for riddimsoftware.com"
  type        = string
  default     = "Z0066450A0OUY8MCI6XV"
}

variable "staging_domain" {
  description = "Custom domain name for the staging API"
  type        = string
  default     = "staging-api.epac.riddimsoftware.com"
}
