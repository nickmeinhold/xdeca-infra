# Kamatera VPS

Kamatera cloud VPS - paid fallback when OCI free tier is unavailable.

## Pricing (Sydney, ~$10-15/mo)

| Config | CPU | RAM | Disk | Monthly |
|--------|-----|-----|------|---------|
| Default | 2 cores | 4GB | 50GB | ~$12/mo |
| Larger | 4 cores | 8GB | 50GB | ~$24/mo |

## Setup

### 1. Get API Credentials

1. Log in to [Kamatera Console](https://console.kamatera.com)
2. Go to **API** → **Keys**
3. Create new API key
4. Note the Client ID and Secret

### 2. Set Environment Variables

```bash
export KAMATERA_API_CLIENT_ID=your-client-id
export KAMATERA_API_SECRET=your-secret
```

### 3. Provision

```bash
cd kamatera-vps
make init
make apply
```

### 4. Deploy Services

```bash
make deploy
```

## Commands

```bash
make help             # Show all commands
make ssh              # SSH to VPS
make ip               # Get public IP
make deploy           # Deploy all services
make logs-openproject # View logs
```

## Switching from OCI

If OCI instance is reclaimed and you need Kamatera:

1. Provision Kamatera: `cd kamatera-vps && make apply`
2. Update DNS to point to new IP
3. Deploy services: `make deploy`
4. Configure backups: `ssh ubuntu@<ip> /opt/scripts/setup-backups.sh`

## Differences from OCI

| Feature | OCI | Kamatera |
|---------|-----|----------|
| Cost | Free | ~$12/mo |
| CPU | 4 ARM | 2 x86 |
| RAM | 24GB | 4GB |
| Availability | Often out of capacity | Always available |
| Keep-alive | Required | Not needed |
