# OpenProject

**Default login:** admin / admin

## Backup

```bash
podman exec openproject_openproject_1 pg_dump -U postgres openproject > backup.sql
```

## Google Calendar Sync

Bidirectional sync between OpenProject milestones and Google Calendar (12pm Melbourne time).

### Architecture

```
OpenProject ──webhook──▶ VPS webhook server ──▶ sync.ts ──▶ Google Calendar
Google Calendar ──push──▶ VPS webhook server ──▶ reverse-sync.ts ──▶ OpenProject
```

Self-hosted on the VPS. No Cloudflare Workers or GitHub Actions needed.

### Files

| File | Purpose |
|------|---------|
| `openproject-calendar-sync/webhook-server.ts` | Webhook receiver (runs on VPS) |
| `openproject-calendar-sync/sync.ts` | Forward sync script |
| `openproject-calendar-sync/reverse-sync.ts` | Reverse sync script |
| `openproject-calendar-sync/watch-setup.ts` | Set up Calendar push notifications |
| `openproject-calendar-sync/secrets.yaml` | SOPS-encrypted secrets |
| `openproject-calendar-sync/calendar-sync.service` | Systemd service file |

### Deployment

Calendar sync is deployed automatically via `make deploy` or `make deploy-calendar-sync`.

**Automated by IaC:**
- Node.js 20, SOPS, age, yq (via Terraform provisioning)
- npm dependencies (via deploy script)
- systemd service installation (via deploy script)
- Caddy reverse proxy route (via deploy script)

**Manual (one-time setup):**
- Create and encrypt `secrets.yaml`
- Copy age key to VPS
- Set up Google Calendar watch

### First-Time Secrets Setup

```bash
# SSH to VPS
ssh ubuntu@103.125.218.210

# Copy age key (one-time)
mkdir -p ~/.config/sops/age
# Copy your age key from local machine to ~/.config/sops/age/keys.txt

# Create secrets file
cd ~/apps/calendar-sync
cp secrets.yaml.example secrets.yaml

# Edit with your values:
# - webhook_secret: generate with: openssl rand -hex 32
# - gcal_webhook_secret: generate with: openssl rand -hex 32
# - openproject_url: https://openproject.enspyr.co
# - openproject_api_key: (from OpenProject admin → API)
# - google_calendar_id: (from Google Calendar settings)
# - google_service_account_json: (from Google Cloud Console)

# Encrypt secrets
sops -e -i secrets.yaml

# Start the service
sudo systemctl enable --now calendar-sync

# Update OpenProject webhook URL to:
# https://calendar-sync.enspyr.co/openproject?token=<WEBHOOK_SECRET>

# Set up Google Calendar watch
make watch-setup
```

### Manual Commands

```bash
make sync           # Forward sync
make reverse-sync   # Reverse sync
make run            # Run webhook server locally
```

### Webhook URLs

Configure in OpenProject and Google Calendar watch:
- OpenProject: `https://calendar-sync.yourdomain.com/openproject?token=<WEBHOOK_SECRET>`
- Google Calendar: `https://calendar-sync.yourdomain.com/gcal?token=<GCAL_WEBHOOK_SECRET>`

## MCP Server Integration (Future)

Potential OpenProject MCP servers for Claude integration:

- [firsthalfhero/openproject-mcp-server](https://github.com/firsthalfhero/openproject-mcp-server)
- [AndyEverything/openproject-mcp-server](https://github.com/AndyEverything/openproject-mcp-server)

Would enable creating/updating work packages, querying project status, and integrating with the `/pm` skill.
