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

### Deployment Status

**Partially deployed on VPS (103.125.218.210)**:
- [x] Node.js 20 installed
- [x] Repo cloned to ~/xdeca-infra
- [x] npm dependencies installed
- [x] SOPS, age, yq installed
- [x] Age key copied
- [ ] secrets.yaml created and encrypted
- [ ] systemd service installed
- [ ] Caddy reverse proxy configured

### Completing Deployment

```bash
# SSH to VPS
ssh ubuntu@103.125.218.210

# Create secrets file
cd ~/xdeca-infra/openproject/openproject-calendar-sync
cp secrets.yaml.example secrets.yaml

# Edit with your values:
# - webhook_secret: (from cloudflare/secrets.yaml)
# - gcal_webhook_secret: (from cloudflare/secrets.yaml)
# - openproject_url: https://openproject.enspyr.co
# - openproject_api_key: (from OpenProject admin → API)
# - google_calendar_id: (from Google Calendar settings)
# - google_service_account_json: (from Google Cloud Console)

# Encrypt secrets
sops -e -i secrets.yaml

# Install systemd service
sudo cp calendar-sync.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now calendar-sync

# Add Caddy route
sudo nano /etc/caddy/Caddyfile
# Add:
# calendar-sync.enspyr.co {
#     reverse_proxy localhost:3001
# }
sudo systemctl reload caddy

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
