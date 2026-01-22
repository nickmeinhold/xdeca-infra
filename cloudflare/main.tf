locals {
  account_id = "fc0bb404a04968a041ca7d8475e2ffad"
}

# OpenProject Calendar Sync Webhook Worker
resource "cloudflare_workers_script" "openproject_calendar_webhook" {
  account_id = local.account_id
  name       = "openproject-calendar-webhook"
  content    = file("${path.module}/../openproject/openproject-calendar-sync/webhook-worker/worker.js")
  module     = true

  secret_text_binding {
    name = "GITHUB_TOKEN"
    text = var.github_token
  }

  secret_text_binding {
    name = "WEBHOOK_SECRET"
    text = var.webhook_secret
  }
}

# Note: workers.dev route is enabled by default when deploying a worker
# The route will be: https://openproject-calendar-webhook.nick-meinhold.workers.dev

# KV namespace for Google Calendar sync state (debouncing, channel info)
resource "cloudflare_workers_kv_namespace" "gcal_sync" {
  account_id = local.account_id
  title      = "gcal-sync-kv"
}

# Google Calendar Reverse Sync Webhook Worker
resource "cloudflare_workers_script" "gcal_calendar_webhook" {
  account_id = local.account_id
  name       = "gcal-calendar-webhook"
  content    = file("${path.module}/../openproject/openproject-calendar-sync/webhook-worker/gcal-worker.js")
  module     = true

  secret_text_binding {
    name = "GITHUB_TOKEN"
    text = var.github_token
  }

  secret_text_binding {
    name = "GCAL_WEBHOOK_SECRET"
    text = var.gcal_webhook_secret
  }

  kv_namespace_binding {
    name         = "GCAL_SYNC_KV"
    namespace_id = cloudflare_workers_kv_namespace.gcal_sync.id
  }
}

# Output the webhook URL for Google Calendar watch setup
output "gcal_webhook_url" {
  value       = "https://gcal-calendar-webhook.nick-meinhold.workers.dev"
  description = "URL for Google Calendar push notifications"
}
