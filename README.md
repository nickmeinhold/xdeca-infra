# xdeca-infra

Infrastructure monorepo for self-hosted services.

📊 [Slides](https://docs.google.com/presentation/d/1FeaD9hIuZ_v6JMNS37dciy7CyX6a7d0m1fT5TG0HGbs/edit)

## Services

| Service | Description | URL |
|---------|-------------|-----|
| [Caddy](./caddy/) | Reverse proxy with automatic HTTPS | - |
| [OpenProject](./openproject/) | Project management | openproject.enspyr.co |
| Calendar Sync | OpenProject ↔ Google Calendar | calendar-sync.enspyr.co |

## Infrastructure

| Provider | Directory | Status | Cost |
|----------|-----------|--------|------|
| Kamatera | [kamatera-vps](./kamatera-vps/) | **Active** | ~$12/mo |
| Oracle Cloud | [oci-vps](./oci-vps/) | Pending | Free |
| Namecheap DNS | [dns](./dns/) | **Active** | - |
| Cloudflare Workers | [cloudflare](./cloudflare/) | Unused | - |

## Architecture

```
Internet → Caddy (443/80) → OpenProject (8080)
                          → Calendar Sync (3001)

OpenProject ──webhook──▶ Calendar Sync ──▶ Google Calendar
Google Calendar ──push──▶ Calendar Sync ──▶ OpenProject
```

## Quick Start

### Prerequisites

```bash
brew install terraform sops age yq
```

### 1. Set up encryption key

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Add public key to .sops.yaml
```

This is the **only unencrypted secret**. Everything else (secrets, terraform state) is encrypted and committed to git.

### 2. Provision infrastructure

```bash
cd kamatera-vps
make init
make apply
```

### 3. Deploy services

```bash
make deploy                 # All services
make deploy-calendar-sync   # Just calendar sync
```

### 4. DNS (run from Pi - IP whitelisted)

```bash
ssh pi
cd ~/xdeca-infra/dns
make apply
```

## Repository Structure

```
.
├── caddy/                  # Reverse proxy config
├── dns/                    # Namecheap DNS (Terraform)
│   ├── main.tf
│   └── secrets.yaml        # SOPS-encrypted
├── openproject/            # Project management
│   └── openproject-calendar-sync/
│       ├── webhook-server.ts
│       ├── sync.ts
│       ├── reverse-sync.ts
│       └── secrets.yaml    # SOPS-encrypted
├── kamatera-vps/           # Kamatera VPS (primary)
│   └── terraform/
│       ├── main.tf
│       ├── startup.sh.tpl
│       └── terraform.tfstate.age
├── oci-vps/                # Oracle Cloud (pending)
├── cloudflare/             # Unused
├── scripts/
│   └── deploy-to.sh        # Deployment script
└── .sops.yaml              # SOPS encryption config
```

## Secrets Management

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).

```bash
# Edit encrypted secrets
sops openproject/secrets.yaml

# Terraform state is also encrypted
# Makefiles handle encrypt/decrypt automatically
make apply   # decrypts state, runs terraform, re-encrypts
```

## License

Private repository.
