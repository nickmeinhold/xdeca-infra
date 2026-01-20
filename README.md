# xdeca-infra

Infrastructure monorepo for self-hosted services on Oracle Cloud free tier.

## Services

| Service | Description | Port |
|---------|-------------|------|
| [Caddy](./caddy/) | Reverse proxy with automatic HTTPS | 80/443 |
| [OpenProject](./openproject/) | Project management | 8080 |
| [Twenty](./twenty/) | CRM (Salesforce alternative) | 3000 |
| [Discourse](./discourse/) | Forum / community platform | 8888 |

## Cloud Providers

| Provider | Directory | Status |
|----------|-----------|--------|
| Oracle Cloud | [oci-vps](./oci-vps/) | Ready (free tier) |
| Kamatera | [kamatera-vps](./kamatera-vps/) | Planned |

## Architecture

```
Internet → Caddy (443/80) → OpenProject (8080)
                          → Twenty (3000)
                          → Discourse (8888)
```

## Quick Start

### Prerequisites

```bash
brew install terraform sops age yq
```

### 1. Set up secrets encryption

```bash
# Create age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Copy the public key (age1...) to .sops.yaml
```

### 2. Create encrypted secrets

```bash
# Copy example and encrypt
cp openproject/openproject.yaml.example openproject/secrets.yaml
# Edit with real values, then encrypt
sops -e -i openproject/secrets.yaml

# Repeat for twenty and discourse
```

### 3. Provision infrastructure

```bash
cd oci-vps
make init
make apply  # May need retries for "Out of capacity"
```

### 4. Deploy services

```bash
make deploy
```

## Repository Structure

```
.
├── caddy/                  # Reverse proxy config
│   ├── Caddyfile
│   └── docker-compose.yml
├── discourse/              # Forum
│   ├── app.yml.example
│   └── discourse.yaml.example
├── openproject/            # Project management
│   ├── docker-compose.yml
│   └── openproject.yaml.example
├── twenty/                 # CRM
│   ├── docker-compose.yml
│   └── twenty.yaml.example
├── oci-vps/                # Oracle Cloud provisioning
│   ├── terraform/
│   ├── scripts/
│   └── Makefile
├── kamatera-vps/           # Kamatera (planned)
├── .sops.yaml              # SOPS encryption config
├── .githooks/              # Git hooks
└── SETUP.md                # Manual setup guide
```

## Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).

```bash
# Edit encrypted secrets (decrypts in place, re-encrypts on save)
sops openproject/secrets.yaml

# Encrypt a new file
sops -e -i myfile.yaml

# Decrypt to stdout
sops -d myfile.yaml
```

A pre-commit hook prevents accidentally committing unencrypted secrets.

### Enable the hook

```bash
git config core.hooksPath .githooks
```

## OCI Free Tier Specs

- **Shape**: VM.Standard.A1.Flex (ARM)
- **OCPUs**: 4
- **RAM**: 24GB
- **Storage**: 50GB
- **Cost**: $0/month

## Backup Strategy

| Data | Method | Destination |
|------|--------|-------------|
| Config | Git | This repo |
| Secrets | Git (SOPS encrypted) | This repo |
| Databases | pg_dump | Oracle Object Storage |
| Discourse | Built-in backup | Oracle Object Storage |

See [discourse/discourse-backup.md](./discourse/discourse-backup.md) for details.

## License

Private repository.
