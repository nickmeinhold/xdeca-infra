# AWS Lightsail VPS

Primary production server for xdeca services.

## Specs

- **Region**: ap-southeast-2 (Sydney)
- **Bundle**: small_3_0 (2GB RAM, 1 vCPU, 60GB SSD)
- **OS**: Ubuntu 24.04
- **Cost**: ~$12/mo

## Quick Start

### Prerequisites

1. AWS CLI configured with credentials:
   ```bash
   aws configure
   ```

2. Create terraform.tfvars:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit with your SSH public key
   ```

### Deploy

```bash
cd lightsail
make init
make apply
make ssh      # SSH into instance
make deploy   # Deploy all services
```

## Commands

| Command | Description |
|---------|-------------|
| `make init` | Initialize Terraform |
| `make plan` | Preview changes |
| `make apply` | Create/update infrastructure |
| `make destroy` | Tear down infrastructure |
| `make ssh` | SSH into the instance |
| `make ip` | Show public IP |
| `make deploy` | Deploy services via deploy-to.sh |

## After Provisioning

1. Run `make deploy` to set up services
2. Configure secrets for each service

## Bundle Options

| Bundle | RAM | vCPU | Storage | Price |
|--------|-----|------|---------|-------|
| nano_3_0 | 512MB | 0.25 | 20GB | $3.50/mo |
| micro_3_0 | 1GB | 0.5 | 40GB | $5/mo |
| small_3_0 | 2GB | 1 | 60GB | $12/mo |
| medium_3_0 | 4GB | 2 | 80GB | $24/mo |
| large_3_0 | 8GB | 2 | 160GB | $48/mo |
