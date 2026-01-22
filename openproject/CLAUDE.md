# OpenProject

**Default login:** admin / admin

## Backup

```bash
podman exec openproject_openproject_1 pg_dump -U postgres openproject > backup.sql
```

## Google Calendar Sync

Bidirectional sync between OpenProject milestones and Google Calendar.

### How It Works

**Forward sync (OpenProject → Calendar):**
1. Milestone created/modified in OpenProject
2. OpenProject webhook triggers Cloudflare Worker
3. Worker dispatches `repository_dispatch` to GitHub Actions
4. `openproject-calendar-sync.yml` runs `sync.ts`
5. Calendar event created/updated with `🎯` prefix

**Reverse sync (Calendar → OpenProject):**
1. Calendar event date changed by user
2. Google Calendar push notification triggers Cloudflare Worker
3. Worker dispatches `gcal_event_changed` to GitHub Actions
4. `gcal-reverse-sync.yml` runs `reverse-sync.ts`
5. OpenProject milestone date updated via API

### Files

| File | Purpose |
|------|---------|
| `openproject-calendar-sync/sync.ts` | Forward sync script |
| `openproject-calendar-sync/reverse-sync.ts` | Reverse sync script |
| `openproject-calendar-sync/watch-setup.ts` | Set up Calendar push notifications |
| `openproject-calendar-sync/webhook-worker/gcal-worker.js` | Cloudflare Worker for Calendar webhooks |

### Loop Prevention

Events have `extendedProperties.private.syncSource = "openproject"` to identify sync-created events. Forward sync skips updating events where the Calendar date differs (user modified it, pending reverse sync).

### Manual Triggers

```bash
# Forward sync
gh workflow run openproject-calendar-sync.yml

# Reverse sync
gh workflow run gcal-reverse-sync.yml
```

## MCP Server Integration (Future)

Potential OpenProject MCP servers for Claude integration:

- [firsthalfhero/openproject-mcp-server](https://github.com/firsthalfhero/openproject-mcp-server)
- [AndyEverything/openproject-mcp-server](https://github.com/AndyEverything/openproject-mcp-server)

Would enable creating/updating work packages, querying project status, and integrating with the `/pm` skill.
