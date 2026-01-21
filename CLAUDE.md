# xdeca Infrastructure

Monorepo for xdeca infrastructure and self-hosted services.

## Structure

```
.
├── caddy/              # Reverse proxy (Caddy)
├── discourse/          # Forum (Discourse)
├── openproject/        # Project management (OpenProject)
├── twenty/             # CRM (Twenty)
├── oci-vps/            # Oracle Cloud provisioning
├── kamatera-vps/       # Kamatera VPS (fallback provider)
├── .sops.yaml          # SOPS encryption config
└── SETUP.md            # Manual setup guide
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| Caddy | 80/443 | Reverse proxy, auto-TLS |
| OpenProject | 8080 | Project management |
| Twenty | 3000 | CRM |
| Discourse | 8888 | Forum |

## Cloud Providers

| Provider | Status | IP | Cost |
|----------|--------|-----|------|
| [oci-vps](./oci-vps/) | Pending | - | Free tier |
| [kamatera-vps](./kamatera-vps/) | **Active** | `103.125.218.210` | ~$12/mo |

## Secrets Management

Secrets use SOPS + age encryption. Each service has a `.yaml.example` template.

```bash
# Setup age key (one-time)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Add public key to .sops.yaml

# Create encrypted secrets from example
cp openproject/openproject.yaml.example openproject/secrets.yaml
sops -e -i openproject/secrets.yaml

# Edit secrets
sops openproject/secrets.yaml
```

## Backup Strategy

| What | Method | Location |
|------|--------|----------|
| Config/Compose | Git | This repo |
| Secrets | Git (SOPS encrypted) | This repo |
| Databases | pg_dump | Oracle Object Storage |
| Discourse | Built-in backup | Oracle Object Storage |

See [discourse/backup.md](./discourse/discourse-backup.md) for Discourse backup details.

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
make init              # Initialize Terraform
make apply             # Create instance (retry if "Out of capacity")
make ssh               # Connect to VPS
```

## Resource IDs

- Tenancy: `ocid1.tenancy.oc1..aaaaaaaa53sr57ghje45q5lkvqunbxbh45imq4rfblzsqvf7vk7y4sjait2a`
- VCN: `ocid1.vcn.oc1.ap-melbourne-1.amaaaaaa2htpxkqahlygi2p7wpfw3hlj3ygbinv4zehq5ay232m2bxzxbn4a`
- Subnet: `ocid1.subnet.oc1.ap-melbourne-1.aaaaaaaa3sxklspcjmiddzuvkq7mlunze2sfm6r6qd3wcb4wmyyrqqmoe24q`
- Image (Ubuntu 24.04): `ocid1.image.oc1.ap-melbourne-1.aaaaaaaaa23ah7oxjhhgcwyd56t6ydtghl2ovzqytnokzrv4233wyqpp5rka`

## OCI CLI

Configured on local machine and Pi:
- Config: `~/.oci/config`
- API Key: `~/.oci/oci_api_key.pem`

## Raspberry Pi

Used for auto-retry provisioning when OCI is out of capacity.

```bash
ssh pi   # Via Tailscale
```

## Keep-Alive

Cloud-init installs a cron job that runs every 6 hours to prevent Oracle from reclaiming idle instances.

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
make init              # Initialize Terraform
make apply             # Create instance
make ssh               # Connect to VPS
make deploy            # Deploy all services
```

## Provisioning from Pi

If your IP keeps changing (mobile hotspot), run terraform from the Pi:

```bash
ssh pi
cd ~/xdeca-infra/kamatera-vps
make apply
```

The Pi has terraform, sops, and age installed, plus the age key for decrypting secrets.

---

# caddy

Reverse proxy with automatic HTTPS via Let's Encrypt.

```
Internet → Caddy (443/80) → OpenProject (8080)
                          → Twenty (3000)
                          → Discourse (8888)
```

Update `Caddyfile` with your domains before deploying.

---

# openproject

Project management. Uses internal PostgreSQL.

- **Default login**: admin / admin
- **Secrets needed**: `SECRET_KEY_BASE`

---

# twenty

CRM (Salesforce alternative). Requires PostgreSQL + Redis.

- **Secrets needed**: Postgres password, 4 JWT tokens

---

# discourse

Forum platform. Uses its own launcher, not docker-compose.

- **Requires**: Working SMTP for email verification
- **Backup**: See [discourse-backup.md](./discourse/discourse-backup.md)

First-time setup:
```bash
cd ~/apps/discourse
./launcher bootstrap app
./launcher start app
```
