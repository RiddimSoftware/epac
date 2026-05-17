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
