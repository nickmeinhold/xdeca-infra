output "webhook_url" {
  description = "URL for the OpenProject webhook (add ?token=<webhook_secret>)"
  value       = "https://openproject-calendar-webhook.nick-meinhold.workers.dev"
}

output "openproject_webhook_config" {
  description = "Full webhook URL to configure in OpenProject"
  value       = "https://openproject-calendar-webhook.nick-meinhold.workers.dev?token=${var.webhook_secret}"
  sensitive   = true
}
