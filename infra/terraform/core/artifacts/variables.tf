variable "bucket_name" {
  description = "Globally unique S3 bucket name for epac artifacts."
  type        = string
}

variable "custom_domain_name" {
  description = "CloudFront alternate domain name for public artifact reads."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.custom_domain_name))
    error_message = "custom_domain_name must be a DNS hostname."
  }
}

variable "route53_zone_name" {
  description = "Public Route 53 hosted zone that owns custom_domain_name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", trimsuffix(var.route53_zone_name, ".")))
    error_message = "route53_zone_name must be a DNS zone name."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days before non-current artifact object versions expire."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags applied to taggable artifact resources."
  type        = map(string)
  default     = {}
}
