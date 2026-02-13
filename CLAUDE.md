# xdeca Infrastructure

Monorepo for xdeca infrastructure and self-hosted services.

## IMPORTANT: Production Server Safety

**DO NOT run repeated/rapid commands on the production server (34.116.110.7).**

The GCE instance has moderate resources (4GB RAM, 2 vCPU) but running many `docker exec`, `docker logs`, or SSH commands in quick succession can still cause issues.

**Instead:**
- Set up a local dev environment to debug issues
- Use `./scripts/deploy-to.sh` for deployments (tested, safe)
- If you must debug production, run commands sparingly with pauses between them
- To recover a crashed server: `gcloud compute instances reset xdeca --zone=australia-southeast1-a`

## Structure

```
.
├── backups/            # Backup config (Google Cloud Storage)
├── caddy/              # Reverse proxy (Caddy)
├── xdeca-pm-bot/       # Telegram bot for Kan.bn
├── kanbn/              # Kanban boards (Trello alternative)
├── outline/            # Team wiki (Notion alternative)
├── scripts/            # Deployment & backup scripts
└── .sops.yaml          # SOPS encryption config
```

## CI & Branch Protection

**Branch protection on `main`:**
- Requires PR with 1 approving review
- Requires all CI checks to pass
- Dismisses stale reviews on new commits

**CI checks (`.github/workflows/ci.yml`):**
- ShellCheck for all bash scripts
- yamllint for docker-compose and workflow files

**Bot accounts (collaborators):**
- `claude-reviewer-max` - PR reviews
- `claude-pm-enspyr` - Project management

## Services

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| Caddy | 80/443 | - | Reverse proxy, auto-TLS |
| Kan.bn | 3003 | tasks.xdeca.com | Kanban boards (Trello-like) |
| xdeca-pm-bot | - | Telegram | AI task assistant for Kan.bn |
| Outline | 3002 | kb.xdeca.com | Team wiki (Notion-like) |
| MinIO | 9000 | storage.xdeca.com | S3-compatible file storage |

## Container Architecture

Each service has its own `docker-compose.yml` and isolated network. Caddy uses `network_mode: host` to bind directly to ports 80/443.

```
                                 Internet
                                     │
                           ┌─────────┴─────────┐
                           │   Caddy (host)    │
                           │   80/443 → TLS    │
                           └─────────┬─────────┘
                                     │
         ┌───────────────────────────┼───────────────────────────┐
         │                           │                           │
         ▼                           ▼                           ▼
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│  kb.xdeca.com   │       │tasks.xdeca.com  │       │storage.xdeca.com│
│   :3002         │       │   :3003         │       │   :9000         │
└────────┬────────┘       └────────┬────────┘       └────────┬────────┘
         │                         │                         │
         ▼                         ▼                         │
┌─────────────────┐       ┌─────────────────┐                │
│    Outline      │       │     Kan.bn      │                │
│  (wiki app)     │       │  (kanban app)   │                │
└────────┬────────┘       └────────┬────────┘                │
         │                         │                         │
    ┌────┴────┐               ┌────┴────┐                    │
    ▼         ▼               ▼         │                    │
┌───────┐ ┌───────┐     ┌─────────┐     │                    │
│Postgres│ │ Redis │     │Postgres │     │    ┌──────────────┘
└───────┘ └───────┘     └─────────┘     │    │
                                        │    ▼
                              ┌─────────┴────────┐
                              │      MinIO       │
                              │ (shared storage) │
                              │ outline, kanbn-* │
                              └──────────────────┘


┌─────────────────────────────────────────────────────────────────────┐
│                      xdeca-pm-bot (standalone)                       │
│                                                                     │
│  ┌──────────┐    HTTP API     ┌──────────┐    Telegram    ┌──────┐ │
│  │  SQLite  │◄───────────────►│  Bot     │◄──────────────►│Users │ │
│  │ (local)  │                 │ (Node.js)│    Polling     │      │ │
│  └──────────┘                 └────┬─────┘                └──────┘ │
│                                    │                                │
│                                    ▼                                │
│                          tasks.xdeca.com                            │
│                          (Kan.bn API)                               │
└─────────────────────────────────────────────────────────────────────┘
```

**Network isolation:**
- `outline/` - own network with postgres, redis, minio
- `kanbn/` - own network with postgres; uses shared MinIO via `storage.xdeca.com`
- `xdeca-pm-bot/` - no docker network; talks to Kan.bn via public API, Telegram via polling
- `caddy/` - `network_mode: host` to bind 80/443 directly

**Shared resources:**
- MinIO (from Outline stack) serves both Outline and Kan.bn file storage
- Caddy routes all HTTPS traffic to backend services on localhost

## Backups

Daily backups to Google Cloud Storage.

| Service | Schedule | Retention |
|---------|----------|-----------|
| Kan.bn | 4 AM | 7 days |
| Outline | 4 AM | 7 days |

```bash
# Manual commands (run on VPS)
/opt/scripts/backup.sh all      # Run backup
/opt/scripts/restore.sh kanbn   # Restore Kan.bn
/opt/scripts/restore.sh outline # Restore Outline
```

## Cloud Provider

| Provider | Status | IP | Cost |
|----------|--------|-----|------|
| GCP Compute Engine (e2-medium) | Active | 34.116.110.7 | ~$24/mo |

## Secrets Management

Everything is encrypted with SOPS/age. The age key is at the default location: `~/.config/sops/age/keys.txt`

**Local decryption:** The key is available on Nick's machine. To decrypt/edit secrets locally, set the env var:
```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
```

```bash
# Setup age key (one-time)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Add public key to .sops.yaml

# Edit encrypted secrets
sops kanbn/secrets.yaml
sops outline/secrets.yaml
```

---

# caddy

Reverse proxy with automatic HTTPS via Let's Encrypt.

```
Internet → Caddy (443/80) → Kan.bn (3003)
                          → Outline (3002)
                          → MinIO Storage (9000)
```

---

# outline

Self-hosted team wiki (Notion alternative). Real-time collaboration with edit history.

**URL**: https://kb.xdeca.com

## Features

- Wiki-style linking between documents
- Real-time collaboration (see cursors, who's editing)
- Edit history with attribution
- Email/password login (via Brevo SMTP)
- Markdown support

## Setup

```bash
# Deploy (secrets auto-decrypted)
./scripts/deploy-to.sh 34.116.110.7 outline
```

First user to sign up becomes admin. Invite team members from Settings → Members.

## Local Development

```bash
cd outline
cp .env.local .env   # Copy local dev template
docker compose up -d # Start all services
```

Access at http://localhost:3002. First signup becomes admin.

**Services:**
- Outline: http://localhost:3002
- MinIO Console: http://localhost:9001 (outline / see .env for password)

**Notes:**
- `.env.local` has pre-generated secrets safe for local dev
- `.env` is gitignored
- Email won't work locally (no SMTP) but signup still works

---

# kanbn

Self-hosted kanban boards (Trello alternative). Using 10xdeca/kan fork.

**URL**: https://tasks.xdeca.com

## Features

- Trello-like kanban boards
- Drag and drop cards
- Labels and filters
- Trello import (boards, cards, lists)
- File attachments (via shared MinIO storage)
- Email/password login

## Storage

Uses shared MinIO instance from Outline for file attachments:
- Buckets: `kanbn-avatars`, `kanbn-attachments`
- Public URL: https://storage.xdeca.com

## Trello Migration

Kan.bn has built-in Trello import via OAuth. To import:

1. Go to Settings → Integrations → Connect Trello
2. Authorize the connection
3. Select boards to import

**Note**: Attachments are NOT imported automatically.

## Setup

```bash
# Deploy (builds from source, secrets auto-decrypted)
./scripts/deploy-to.sh 34.116.110.7 kanbn
```

First user to sign up becomes admin.

---

# xdeca-pm-bot

Telegram bot for Kan.bn task management. Uses Claude AI for natural language interaction.

**Source**: [10xdeca/xdeca-pm-bot](https://github.com/10xdeca/xdeca-pm-bot)

## Features

- Task reminders via Telegram
- Sprint tracking
- AI-powered task assistance (Claude)

## Config

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token |
| `KAN_BASE_URL` | Kan.bn URL (default: tasks.xdeca.com) |
| `KAN_SERVICE_API_KEY` | API key for Kan.bn |
| `ANTHROPIC_API_KEY` | Claude API key |
| `SPRINT_START_DATE` | Sprint start date |
| `REMINDER_INTERVAL_HOURS` | Reminder frequency |

## Setup

```bash
# Deploy (source from https://github.com/10xdeca/xdeca-pm-bot)
./scripts/deploy-to.sh 34.116.110.7 xdeca-pm-bot

# Check logs
ssh 34.116.110.7 'docker logs -f xdeca-pm-bot'
```
