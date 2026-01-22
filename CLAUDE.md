# xdeca Infrastructure

Monorepo for xdeca infrastructure and self-hosted services.

## Structure

```
.
├── caddy/              # Reverse proxy (Caddy)
├── cloudflare/         # Cloudflare Terraform (unused)
├── discourse/          # Forum (Discourse)
├── openproject/        # Project management + calendar sync
├── twenty/             # CRM (Twenty)
├── oci-vps/            # Oracle Cloud provisioning
├── kamatera-vps/       # Kamatera VPS (primary)
└── .sops.yaml          # SOPS encryption config
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| Caddy | 80/443 | Reverse proxy, auto-TLS |
| OpenProject | 8080 | Project management |
| Twenty | 3000 | CRM |
| Discourse | 8888 | Forum |

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

## Cloud Providers

| Provider | Status | IP | Cost |
|----------|--------|-----|------|
| [oci-vps](./oci-vps/) | Pending | - | Free tier |
| [kamatera-vps](./kamatera-vps/) | **Active** | `103.125.218.210` | ~$12/mo |
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
- **IP**: `103.125.218.210`

## Quick Start

```bash
cd kamatera-vps
make init
make apply
make ssh
make deploy   # Deploy all services
```

---

# caddy

Reverse proxy with automatic HTTPS via Let's Encrypt.

```
Internet → Caddy (443/80) → OpenProject (8080)
                          → Twenty (3000)
                          → Discourse (8888)
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
