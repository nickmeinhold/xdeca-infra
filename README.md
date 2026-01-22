# xdeca-infra

Infrastructure monorepo for self-hosted services.

## Services

| Service | Description | Port |
|---------|-------------|------|
| [Caddy](./caddy/) | Reverse proxy with automatic HTTPS | 80/443 |
| [OpenProject](./openproject/) | Project management | 8080 |
| [Twenty](./twenty/) | CRM (Salesforce alternative) | 3000 |
| [Discourse](./discourse/) | Forum / community platform | 8888 |

## Infrastructure

| Provider | Directory | Status | Cost |
|----------|-----------|--------|------|
| Oracle Cloud | [oci-vps](./oci-vps/) | Pending | Free |
| Kamatera | [kamatera-vps](./kamatera-vps/) | **Active** | ~$12/mo |
| Cloudflare Workers | [cloudflare](./cloudflare/) | **Active** | Free |

## Integrations

| From | To | Trigger |
|------|----|---------|
| OpenProject | Google Calendar | Milestone webhook → GitHub Actions |

## Architecture

```
Internet → Caddy (443/80) → OpenProject (8080)
                          → Twenty (3000)
                          → Discourse (8888)

OpenProject → Cloudflare Worker → GitHub Actions → Google Calendar
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
cd kamatera-vps   # or oci-vps
make init
make apply
```

### 3. Deploy services

```bash
make deploy
```

## Repository Structure

```
.
├── caddy/                  # Reverse proxy config
├── cloudflare/             # Cloudflare Workers (Terraform)
│   ├── main.tf
│   ├── secrets.yaml        # SOPS-encrypted
│   └── terraform.tfstate.age
├── discourse/              # Forum
├── openproject/            # Project management
│   └── openproject-calendar-sync/  # Calendar integration
├── twenty/                 # CRM
├── oci-vps/                # Oracle Cloud provisioning
│   └── terraform/
├── kamatera-vps/           # Kamatera VPS
│   └── terraform/
├── scripts/                # Shared scripts
├── .github/workflows/      # GitHub Actions
│   └── openproject-calendar-sync.yml
└── .sops.yaml              # SOPS encryption config
```

## Secrets Management

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).

```bash
# Edit encrypted secrets
sops openproject/secrets.yaml

# Terraform state is also encrypted
# Makefiles handle encrypt/decrypt automatically
make apply   # decrypts state, runs terraform, re-encrypts, deletes plaintext
```

## License

Private repository.
