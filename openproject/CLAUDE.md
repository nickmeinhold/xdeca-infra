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

### Deployment (VPS)

```bash
# Install
cd ~/xdeca-infra/openproject/openproject-calendar-sync
make install

# Set up secrets (one-time)
make secrets-create
# Edit secrets.yaml with credentials
sops -e -i secrets.yaml

# Install systemd service
sudo cp calendar-sync.service /etc/systemd/system/
sudo systemctl enable calendar-sync
sudo systemctl start calendar-sync

# Add Caddy routes (in Caddyfile)
# calendar-sync.yourdomain.com {
#     reverse_proxy localhost:3001
# }
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
