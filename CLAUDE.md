# xdeca Infrastructure

Monorepo for xdeca infrastructure and self-hosted services.

## Structure

```
.
├── backups/            # Backup config (OCI Object Storage)
├── caddy/              # Reverse proxy (Caddy)
├── cloudflare/         # Cloudflare Terraform (unused)
├── discourse/          # Forum (Discourse)
├── dns/                # Namecheap DNS (Terraform)
├── openproject/        # Project management + calendar sync
├── twenty/             # CRM (Twenty)
├── oci-vps/            # Oracle Cloud provisioning
├── kamatera-vps/       # Kamatera VPS (primary)
├── scripts/            # Deployment & backup scripts
├── docs/               # Documentation
└── .sops.yaml          # SOPS encryption config
```

## Services

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| Caddy | 80/443 | - | Reverse proxy, auto-TLS |
| OpenProject | 8080 | openproject.enspyr.co | Project management |
| Twenty | 3000 | twenty.enspyr.co | CRM |
| Discourse | 8888 | discourse.enspyr.co | Forum |
| Calendar Sync | 3001 | calendar-sync.enspyr.co | OpenProject ↔ Google Calendar |

## Integrations

| Integration | Trigger | Action |
|-------------|---------|--------|
| OpenProject ↔ Google Calendar | Bidirectional | Milestones sync via VPS webhook server |

### Calendar Sync Architecture

```
OpenProject ──webhook──▶ VPS ──▶ Google Calendar
Google Calendar ──push──▶ VPS ──▶ OpenProject
```

Self-hosted webhook server on VPS. Events appear at 12pm Melbourne time.

**Status**: Automated via IaC. First deploy requires secrets setup. See `openproject/CLAUDE.md`.

## Backups

Daily backups to Oracle Cloud Object Storage (Standard tier, first 10GB free).

| Service | Schedule | Retention |
|---------|----------|-----------|
| OpenProject | 4 AM | 7 days |
| Twenty | 4 AM | 7 days |
| Discourse | 3 AM | 7 days |

**Status**: Automated via IaC. First deploy requires `backups/secrets.yaml`. See `docs/backups.md`.

**Auto-restore**: On `make deploy`, if databases are empty and backups exist, restores automatically.

```bash
# Disaster recovery (auto-restores)
make apply && make deploy

# Manual commands
make backup-now    # Run backup
make backup-test   # Test connection
make restore       # Force restore from latest
```

## Cloud Providers

| Provider | Status | IP | Cost |
|----------|--------|-----|------|
| [oci-vps](./oci-vps/) | Pending | - | Free tier |
| [kamatera-vps](./kamatera-vps/) | **Active** | `45.151.153.65` | ~$12/mo |
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

Oracle Cloud Always Free tier VPS.

## Specs

- **Shape**: VM.Standard.A1.Flex (ARM)
- **OCPUs**: 4
- **RAM**: 24GB
- **Storage**: 50GB
- **Region**: ap-melbourne-1

## Quick Start

```bash
cd oci-vps
make init
make apply   # Retry if "Out of capacity"
make ssh
```

## Auto-Retry Provisioning

The Pi runs a cron job every 5 minutes to retry provisioning until successful:

```bash
ssh pi "tail ~/oci-provision.log"
```

---

# kamatera-vps

Kamatera cloud VPS - paid fallback when OCI free tier is unavailable.

## Specs

- **CPU**: 2 cores (x86)
- **RAM**: 4GB
- **Storage**: 50GB
- **Region**: Sydney, Australia
- **IP**: `45.151.153.65`

## Quick Start

```bash
cd kamatera-vps
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
Internet → Caddy (443/80) → OpenProject (8080)
                          → Twenty (3000)
                          → Discourse (8888)
                          → Calendar Sync (3001)
```

---

# openproject

Project management. Uses internal PostgreSQL.

- **Default login**: admin / admin
- **Calendar sync**: Bidirectional sync with Google Calendar (milestones only)

---

# twenty

CRM (Salesforce alternative). Requires PostgreSQL + Redis.

---

# discourse

Forum platform. Uses its own launcher, not docker-compose.

```bash
cd ~/apps/discourse
./launcher bootstrap app
./launcher start app
```
