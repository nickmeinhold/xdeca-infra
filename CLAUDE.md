# xdeca Infrastructure

Monorepo for xdeca infrastructure and self-hosted services.

## Structure

```
.
├── backups/            # Backup config (AWS S3)
├── caddy/              # Reverse proxy (Caddy)
├── cloudflare/         # Cloudflare Terraform (unused)
├── dns/                # Namecheap DNS (Terraform)
├── kanbn/              # Kanban boards (Trello alternative)
├── outline/            # Team wiki (Notion alternative)
├── oci-vps/            # Oracle Cloud provisioning
├── lightsail/          # AWS Lightsail VPS (primary)
├── scripts/            # Deployment & backup scripts
├── docs/               # Documentation
└── .sops.yaml          # SOPS encryption config
```

## Services

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| Caddy | 80/443 | - | Reverse proxy, auto-TLS |
| Kan.bn | 3003 | kanbn.enspyr.co | Kanban boards (Trello-like) |
| Outline | 3002 | wiki.enspyr.co | Team wiki (Notion-like) |
| MinIO | 9000 | storage.enspyr.co | S3-compatible file storage |
| ~~OpenProject~~ | ~~8080~~ | ~~openproject.enspyr.co~~ | Stopped (replaced by Kan.bn) |

## Integrations

| Integration | Status | Description |
|-------------|--------|-------------|
| Kan.bn ↔ Google Calendar | Pending | Waiting for webhook PR to be merged |

### Calendar Sync (Pending)

Contributed webhooks to Kan.bn: https://github.com/kanbn/kan/pull/343

Once merged, will enable bidirectional sync between Kan.bn card due dates and Google Calendar.

## Backups

Daily backups to AWS S3.

| Service | Schedule | Retention |
|---------|----------|-----------|
| Kan.bn | 4 AM | 7 days |
| Outline | 4 AM | 7 days |

**Status**: Automated via IaC. First deploy requires `backups/secrets.yaml`. See `docs/backups.md`.

```bash
# Manual commands
make backup-now    # Run backup
make backup-test   # Test connection
```

## Cloud Providers

| Provider | Status | IP | Cost |
|----------|--------|-----|------|
| [lightsail](./lightsail/) | Active | 13.54.159.183 | ~$12/mo |
| [oci-vps](./oci-vps/) | Pending | - | Free tier |
| [cloudflare](./cloudflare/) | Unused | - | Free tier |

## Secrets Management

Everything is encrypted. Only one secret exists unencrypted: `~/.config/sops/age/keys.txt`

```bash
# Setup age key (one-time)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Add public key to .sops.yaml

# Edit encrypted secrets
sops openproject/secrets.yaml
```

Terraform state is also encrypted (`*.tfstate.age`) and committed to git.

---

# cloudflare

Cloudflare Terraform configuration. Currently unused - calendar sync moved to VPS.

```bash
cd cloudflare
make destroy  # Remove old workers from Cloudflare
```

---

# oci-vps

Oracle Cloud Always Free tier VPS. Two accounts configured for parallel provisioning attempts.

## Accounts

| Account | Region | Status |
|---------|--------|--------|
| Melbourne | ap-melbourne-1 | Pending |
| Sydney | ap-sydney-1 | Pending |

## Specs (per instance)

- **Shape**: VM.Standard.A1.Flex (ARM)
- **OCPUs**: 4
- **RAM**: 24GB
- **Storage**: 50GB

## Auto-Retry Provisioning

The Pi runs a cron job every 5 minutes to retry both accounts until one succeeds:

```bash
ssh pi "tail ~/oci-provision.log"
```

Notifications via ntfy.sh topic `xdeca-oci-alerts` when provisioned.

---

# lightsail

AWS Lightsail VPS - primary production server.

## Specs

- **CPU**: 1 vCPU
- **RAM**: 2GB
- **Storage**: 60GB SSD
- **Region**: Sydney (ap-southeast-2)
- **Cost**: ~$12/mo

## Quick Start

```bash
cd lightsail
make init
make apply
make ssh
make deploy   # Deploy all services
```

---

# dns

Namecheap DNS records managed via Terraform.

```bash
cd dns
make plan    # Preview changes
make apply   # Apply (requires whitelisted IP - run from Pi)
```

**Note**: Namecheap API requires IP whitelisting. Run from Pi which is already whitelisted.

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

**URL**: https://wiki.enspyr.co

## Features

- Wiki-style linking between documents
- Real-time collaboration (see cursors, who's editing)
- Edit history with attribution
- Email/password login (via Brevo SMTP)
- Markdown support

## Current Auth

Uses email/password authentication (not Google OAuth - that requires Workspace accounts).
SMTP via Brevo (same credentials as OpenProject in `openproject/secrets.yaml`).

## Setup

**Status**: Fully automated via IaC. Secrets encrypted with SOPS.

```bash
# Deploy (secrets auto-decrypted)
./scripts/deploy-to.sh 13.54.159.183 outline
```

### First-Time Secrets Setup

```bash
# Copy template
cp outline/secrets.yaml.example outline/secrets.yaml

# Edit with your values (generate secrets with: openssl rand -hex 32)
nano outline/secrets.yaml

# Encrypt
sops -e -i outline/secrets.yaml

# Deploy
./scripts/deploy-to.sh 13.54.159.183 outline
```

## First Login

First user to sign up becomes admin. Invite team members from Settings → Members.

---

# kanbn

Self-hosted kanban boards (Trello alternative). Lightweight and fast.

**URL**: https://kanbn.enspyr.co

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
- Public URL: https://storage.enspyr.co

## Trello Migration

Kan.bn has built-in Trello import via OAuth. To import:

1. Go to Settings → Integrations → Connect Trello
2. Authorize the connection
3. Select boards to import

**Note**: Attachments are NOT imported automatically. Use the Trello API to download attachments separately if needed.

## Setup

**Status**: Fully automated via IaC. Secrets encrypted with SOPS.

```bash
# Deploy (secrets auto-decrypted)
./scripts/deploy-to.sh 13.54.159.183 kanbn
```

## First Login

First user to sign up becomes admin.
