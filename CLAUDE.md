# xdeca Infrastructure

Monorepo for xdeca infrastructure and self-hosted services.

## Structure

```
.
├── backups/            # Backup config (AWS S3)
├── caddy/              # Reverse proxy (Caddy)
├── dns/                # DNS (Terraform) - xdeca.com only
├── kanbn/              # Kanban boards (Trello alternative)
├── outline/            # Team wiki (Notion alternative)
├── lightsail/          # AWS Lightsail VPS (primary)
├── scripts/            # Deployment & backup scripts
└── .sops.yaml          # SOPS encryption config
```

## CI & Branch Protection

**Branch protection on `main`:**
- Requires PR with 1 approving review
- Requires all CI checks to pass
- Dismisses stale reviews on new commits

**CI checks (`.github/workflows/ci.yml`):**
- Terraform fmt + validate (dns, lightsail, oci-vps/terraform)
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
| Outline | 3002 | wiki.xdeca.com | Team wiki (Notion-like) |
| MinIO | 9000 | storage.xdeca.com | S3-compatible file storage |

## Backups

Daily backups to AWS S3.

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

## Cloud Providers

| Provider | Status | IP | Cost |
|----------|--------|-----|------|
| [lightsail](./lightsail/) | Active | 13.54.159.183 | ~$12/mo |
| [oci-vps](./oci-vps/) | Pending | - | Free tier |

## Secrets Management

Everything is encrypted with SOPS/age. Only one secret exists unencrypted: `~/.config/sops/age/keys.txt`

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

DNS records managed via Terraform (xdeca.com on Namecheap).

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

**URL**: https://wiki.xdeca.com

## Features

- Wiki-style linking between documents
- Real-time collaboration (see cursors, who's editing)
- Edit history with attribution
- Email/password login (via Brevo SMTP)
- Markdown support

## Setup

```bash
# Deploy (secrets auto-decrypted)
./scripts/deploy-to.sh 13.54.159.183 outline
```

First user to sign up becomes admin. Invite team members from Settings → Members.

---

# kanbn

Self-hosted kanban boards (Trello alternative). Using 10xdeca/kan fork with webhook support.

**URL**: https://tasks.xdeca.com

## Features

- Trello-like kanban boards
- Drag and drop cards
- Labels and filters
- Trello import (boards, cards, lists)
- File attachments (via shared MinIO storage)
- Email/password login
- Webhooks (10xdeca fork)

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
./scripts/deploy-to.sh 13.54.159.183 kanbn
```

First user to sign up becomes admin.
