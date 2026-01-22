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
