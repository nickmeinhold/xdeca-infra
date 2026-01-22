# Cloudflare Workers

Terraform-managed Cloudflare Workers for xdeca integrations.

## Workers

| Worker | URL | Purpose |
|--------|-----|---------|
| openproject-calendar-webhook | `*.nick-meinhold.workers.dev` | Receives OpenProject webhooks, triggers GitHub Actions |

## Quick Start

```bash
cd cloudflare
make init          # Initialize Terraform
make plan          # Preview changes
make apply         # Deploy changes
```

## Secrets

Secrets are SOPS-encrypted in `secrets.yaml`:

| Secret | Description |
|--------|-------------|
| `cloudflare_api_token` | Cloudflare API token with Workers edit permission |
| `github_token` | GitHub PAT with `repo` scope for repository_dispatch |
| `webhook_secret` | Shared secret for verifying OpenProject webhooks |

## Architecture

```
OpenProject → Cloudflare Worker → GitHub Actions → Google Calendar
     (webhook)    (webhook-worker)   (repository_dispatch)    (sync)
```

## Webhook URL

```bash
make webhook-url   # Shows full URL with token
```

Configure in OpenProject: **Administration → Webhooks**
