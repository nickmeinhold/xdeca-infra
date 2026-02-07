# xdeca-infra

Infrastructure monorepo for self-hosted services.

## Services

| Service | Description | URL |
|---------|-------------|-----|
| [Kan.bn](./kanbn/) | Kanban boards (Trello alternative) | tasks.xdeca.com |
| [Outline](./outline/) | Team wiki (Notion alternative) | wiki.xdeca.com |
| MinIO | S3-compatible file storage | storage.xdeca.com |
| [Caddy](./caddy/) | Reverse proxy with automatic HTTPS | - |

## Infrastructure

| Provider | Directory | Status | Cost |
|----------|-----------|--------|------|
| AWS Lightsail | [lightsail](./lightsail/) | **Active** | ~$12/mo |
| Oracle Cloud | [oci-vps](./oci-vps/) | Pending | Free |

## Architecture

```
Internet → Caddy (443/80) → Kan.bn (3003)
                          → Outline (3002)
                          → MinIO (9000)
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

### 2. Deploy services

```bash
./scripts/deploy-to.sh 13.54.159.183 all
```

## Repository Structure

```
.
├── caddy/                  # Reverse proxy config
├── kanbn/                  # Kan.bn (Trello alternative)
├── outline/                # Outline wiki
├── lightsail/              # AWS Lightsail VPS
├── backups/                # Backup configuration
├── scripts/
│   ├── deploy-to.sh        # Deployment script
│   ├── backup.sh           # Backup script
│   └── restore.sh          # Restore script
└── .sops.yaml              # SOPS encryption config
```

## Secrets Management

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).

```bash
# Edit encrypted secrets
sops kanbn/secrets.yaml
sops outline/secrets.yaml
```
