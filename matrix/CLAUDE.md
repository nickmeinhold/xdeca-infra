# Matrix Synapse

Self-hosted Matrix homeserver with optional bridges.

## Requirements

- 2-4 GB RAM (Synapse + PostgreSQL)
- Additional ~50-100 MB per bridge
- Domain pointing to server
- Ports: 443 (client), 8448 (federation)

## Setup

### 1. Create .env file

```bash
cp .env.example .env
# Edit with your values
```

### 2. Generate Synapse config

```bash
docker run -it --rm \
  -v $(pwd)/synapse_data:/data \
  -e SYNAPSE_SERVER_NAME=yourdomain.com \
  -e SYNAPSE_REPORT_STATS=no \
  matrixdotorg/synapse:latest generate
```

### 3. Configure homeserver.yaml

Edit `synapse_data/homeserver.yaml`:

```yaml
# Database (use PostgreSQL, not SQLite)
database:
  name: psycopg2
  args:
    user: synapse
    password: your-postgres-password
    database: synapse
    host: db
    cp_min: 5
    cp_max: 10

# Server name
server_name: "yourdomain.com"

# Listeners
listeners:
  - port: 8008
    type: http
    tls: false
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false

# Registration (disable for private server)
enable_registration: false
enable_registration_without_verification: false

# Admin user (create after first start)
# docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008 -a
```

### 4. Start services

```bash
docker compose up -d
```

### 5. Create admin user

```bash
docker compose exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  http://localhost:8008 -a
```

## Caddy Config

Add to Caddyfile:

```
matrix.yourdomain.com {
    reverse_proxy /_matrix/* localhost:8008
    reverse_proxy /_synapse/* localhost:8008
}

# Federation (optional - can also use .well-known)
yourdomain.com:8448 {
    reverse_proxy localhost:8008
}
```

Or use .well-known delegation (add to main domain):

```
yourdomain.com {
    handle /.well-known/matrix/server {
        respond `{"m.server": "matrix.yourdomain.com:443"}`
    }
    handle /.well-known/matrix/client {
        respond `{"m.homeserver": {"base_url": "https://matrix.yourdomain.com"}}`
    }
}
```

## Bridges

### Enable a bridge

1. Uncomment in docker-compose.yml
2. Generate bridge config:

```bash
# Example for Telegram
docker run --rm -v $(pwd)/telegram_data:/data dock.mau.dev/mautrix/telegram:latest
```

3. Edit config in `telegram_data/config.yaml`:
   - Set homeserver URL
   - Set bridge permissions
   - Add Telegram API credentials

4. Register bridge with Synapse (add to homeserver.yaml):

```yaml
app_service_config_files:
  - /data/telegram-registration.yaml
```

5. Restart: `docker compose up -d`

### Bridge setup guides

- **Telegram**: Requires API ID/hash from https://my.telegram.org
- **Discord**: Just works, login via bot
- **Signal**: Requires linked device
- **WhatsApp**: Requires QR code scan

## Clients

- **Element Web**: Self-host or use app.element.io
- **Element Desktop/Mobile**: Point to your homeserver
- **FluffyChat**: Good mobile alternative

## RAM Usage (typical)

| Component | RAM |
|-----------|-----|
| Synapse | 200-500 MB |
| PostgreSQL | 100-200 MB |
| Each bridge | 50-100 MB |
| **Total (4 bridges)** | ~800 MB - 1.2 GB |

## Backup

```bash
# Database
docker compose exec db pg_dump -U synapse synapse > synapse_backup.sql

# Media and config
tar czf synapse_data_backup.tar.gz synapse_data/
```
