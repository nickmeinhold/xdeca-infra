variable "cloudflare_api_token" {
  description = "Cloudflare API token with Workers permissions"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub PAT for triggering repository_dispatch"
  type        = string
  sensitive   = true
}

variable "webhook_secret" {
  description = "Shared secret for verifying OpenProject webhook requests"
  type        = string
  sensitive   = true
}
