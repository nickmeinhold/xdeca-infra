# Obsidian LiveSync

Self-hosted sync for Obsidian using CouchDB.

## Requirements

- ~128-256 MB RAM
- SSL certificate (required for mobile sync)
- Domain pointing to server

## Setup

### 1. Create .env file

```bash
cp .env.example .env
# Edit with your values
```

### 2. Start CouchDB

```bash
docker compose up -d
```

### 3. Configure CouchDB for LiveSync

After first start, run the setup script or configure manually:

```bash
# Access CouchDB admin UI
# https://obsidian.yourdomain.com/_utils

# Or use curl to configure:
curl -X PUT http://admin:password@localhost:5984/_users
curl -X PUT http://admin:password@localhost:5984/_replicator
curl -X PUT http://admin:password@localhost:5984/_global_changes

# Set CORS (required for plugin)
curl -X PUT http://admin:password@localhost:5984/_node/_local/_config/httpd/enable_cors -d '"true"'
curl -X PUT http://admin:password@localhost:5984/_node/_local/_config/cors/origins -d '"*"'
curl -X PUT http://admin:password@localhost:5984/_node/_local/_config/cors/credentials -d '"true"'
curl -X PUT http://admin:password@localhost:5984/_node/_local/_config/cors/methods -d '"GET, PUT, POST, HEAD, DELETE"'
curl -X PUT http://admin:password@localhost:5984/_node/_local/_config/cors/headers -d '"accept, authorization, content-type, origin, referer, x-csrf-token"'

# Set max document size (for large notes)
curl -X PUT http://admin:password@localhost:5984/_node/_local/_config/couchdb/max_document_size -d '"50000000"'
```

### 4. Create database for vault

```bash
curl -X PUT http://admin:password@localhost:5984/obsidian
```

### 5. Configure Obsidian plugin

1. Install "Self-hosted LiveSync" from Community plugins
2. Settings → Remote Configuration:
   - URI: `https://obsidian.yourdomain.com`
   - Username: `obsidian` (from .env)
   - Password: (from .env)
   - Database name: `obsidian`
3. Enable sync

## Caddy Config

Add to Caddyfile:

```
obsidian.yourdomain.com {
    reverse_proxy localhost:5984
}
```

## Multiple Vaults

Create separate databases for each vault:

```bash
curl -X PUT http://admin:password@localhost:5984/vault-work
curl -X PUT http://admin:password@localhost:5984/vault-personal
```

## Backup

CouchDB data is in the `couchdb_data` volume:

```bash
docker compose exec couchdb tar czf - /opt/couchdb/data > backup.tar.gz
```
