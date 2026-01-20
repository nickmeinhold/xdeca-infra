# BigBlueButton

Web conferencing system for online meetings and virtual classrooms.

## Requirements

BigBlueButton is resource-intensive (video/audio processing). Recommended:
- **CPU**: 4+ cores
- **RAM**: 8GB+ (16GB recommended)
- **Disk**: 50GB+
- **Ports**: 80, 443, UDP 16384-32768

This likely needs its own VPS or a larger instance than the shared services.

## Installation

BigBlueButton uses its own install script (not Docker):

```bash
# SSH to dedicated VPS
ssh ubuntu@<bbb-ip>

# Download and run installer
wget -qO- https://raw.githubusercontent.com/bigbluebutton/bbb-install/v3.0.x-release/bbb-install.sh | bash -s -- -w -v jammy-300 -s bbb.yourdomain.com -e admin@yourdomain.com
```

### Install Script Options

- `-w` - Install with HTTPS (Let's Encrypt)
- `-v jammy-300` - BigBlueButton 3.0 on Ubuntu 22.04
- `-s` - Hostname for the server
- `-e` - Email for Let's Encrypt

## Configuration

After installation:

```bash
# Check status
bbb-conf --check

# Get join URL for testing
bbb-conf --secret

# Restart services
bbb-conf --restart
```

## Greenlight (Optional)

Greenlight is a simple frontend for BigBlueButton:

```bash
# Add Greenlight during install
wget -qO- https://raw.githubusercontent.com/bigbluebutton/bbb-install/v3.0.x-release/bbb-install.sh | bash -s -- -w -v jammy-300 -s bbb.yourdomain.com -e admin@yourdomain.com -g
```

## Deployment Options

1. **Dedicated OCI instance** - If you can get capacity (free)
2. **Dedicated Kamatera instance** - ~$24/mo for 4 CPU, 8GB RAM
3. **Separate from other services** - BBB shouldn't share resources

## Integration

BigBlueButton can integrate with:
- Moodle
- Discourse (via plugin)
- Custom apps (via API)

## API

```bash
# Get shared secret
bbb-conf --secret

# API endpoint
https://bbb.yourdomain.com/bigbluebutton/api
```
