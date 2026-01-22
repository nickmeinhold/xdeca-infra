# Cloudflare Workers

Terraform-managed Cloudflare Workers.

## Workers

| Worker | Purpose |
|--------|---------|
| `openproject-calendar-webhook` | OpenProject webhook → GitHub Actions |

**URL**: `https://openproject-calendar-webhook.nick-meinhold.workers.dev`

## Commands

```bash
make init          # Initialize Terraform
make plan          # Preview changes
make apply         # Deploy
make webhook-url   # Show webhook URL with token
```

## Architecture

```
OpenProject → Cloudflare Worker → GitHub Actions → Google Calendar
   (webhook)   (this worker)      (repository_dispatch)    (sync)
```

## Secrets

SOPS-encrypted in `secrets.yaml`:

- `cloudflare_api_token` - Cloudflare API token
- `github_token` - GitHub PAT with `repo` scope
- `webhook_secret` - Shared secret for webhook auth
