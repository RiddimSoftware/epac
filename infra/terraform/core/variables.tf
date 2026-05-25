variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "artifacts_bucket_name" {
  description = "Globally unique S3 bucket name for epac artifacts."
  type        = string
  default     = "epac-artifacts-227530433709"
}

variable "artifacts_custom_domain_name" {
  description = "CloudFront alternate domain name for public artifact reads."
  type        = string
  default     = "epac-assets.riddimsoftware.com"
}

variable "artifacts_route53_zone_name" {
  description = "Public Route 53 hosted zone that owns artifacts_custom_domain_name."
  type        = string
  default     = "riddimsoftware.com"
}

variable "lambda_role_name" {
  description = "Existing EPAC Lambda execution role name."
  type        = string
  default     = "epac-lambda-role"
}

variable "hansard_search_prefix" {
  description = "S3 key prefix used by the Hansard search index artifact."
  type        = string
  default     = "hansard-search/v1"
}
