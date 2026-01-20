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
├── discourse/              # Forum
├── openproject/            # Project management
├── twenty/                 # CRM
├── oci-vps/                # Oracle Cloud provisioning
│   ├── terraform/
│   └── Makefile
├── kamatera-vps/           # Kamatera (planned)
├── scripts/                # Shared scripts
│   ├── backup.sh           # Backup all services
│   ├── restore.sh          # Restore from backup
│   └── setup-backups.sh    # Configure backup infra
├── docs/                   # Documentation
│   └── backups.md
├── .githooks/              # Git hooks (pre-commit)
└── .sops.yaml              # SOPS encryption config
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

## Backups

All services backup daily to Oracle Object Storage (Archive tier, free up to 10GB).

| Service | Data | Schedule | Retention |
|---------|------|----------|-----------|
| OpenProject | PostgreSQL | Daily 4 AM | 7 days |
| Twenty | PostgreSQL + files | Daily 4 AM | 7 days |
| Discourse | Built-in backup | Daily 3 AM | 7 days |

Setup after provisioning:
```bash
ssh ubuntu@<vps-ip>
./scripts/setup-backups.sh
```

See [docs/backups.md](./docs/backups.md) for full backup & restore documentation.

## License

Private repository.
