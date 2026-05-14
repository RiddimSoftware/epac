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

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for riddimsoftware.com"
  type        = string
  default     = "Z0066450A0OUY8MCI6XV"
}

variable "production_domain" {
  description = "Custom domain name for the production API"
  type        = string
  default     = "api.epac.riddimsoftware.com"
}

variable "production_certificate_arn" {
  description = "ACM certificate ARN for the production API custom domain"
  type        = string
  default     = "arn:aws:acm:us-east-1:227530433709:certificate/f921ddcd-6d4d-4377-8b4e-00cea46d92a6"
}
