# VPS Toolbox

A collection of shell scripts for one-click V2Ray deployment (WebSocket + TLS + Web) and GoDaddy DNS management.

---

## Prerequisites

### 1. VPS Server

You need an overseas VPS server (Debian / Ubuntu, with root access).

[Vultr](https://www.vultr.com/?ref=7163300) is recommended — new users who sign up via this referral link receive bonus credits.

### 2. Domain & GoDaddy DNS (Optional, for DNS Management)

If you want to use the one-click DNS management feature, you need to manage your domain through GoDaddy:

1. Register a [GoDaddy](https://www.godaddy.com) account
2. Purchase a domain
3. Obtain your Open API Key and Secret — [Go to GoDaddy Developer](https://developer.godaddy.com/keys)

> If you already own a domain and have manually configured a DNS A record pointing to your VPS IP, you can skip this step and use `v2ray-deploy.sh` directly.

---

## v2ray-deploy.sh

One-click deployment of V2Ray + Nginx + WebSocket + TLS on a Debian/Ubuntu VPS, with support for domain name changes.

### Prerequisites

- Debian / Ubuntu system
- Root access
- A purchased domain with a DNS A record pointing to the server IP

### Commands

```bash
# Full initial deployment
bash v2ray-deploy.sh install

# Change domain only (keeps UUID, port, and path unchanged; re-issues certificate)
bash v2ray-deploy.sh change-domain

# View current configuration and client connection parameters
bash v2ray-deploy.sh info
```

### install Workflow

The script will interactively prompt for the following (press Enter to use auto-generated defaults):

| Parameter | Description | Default |
|-----------|-------------|---------|
| Domain | Required, e.g. `dev.example.com` | - |
| UUID | V2Ray user ID | Auto-generated random UUID |
| Port | V2Ray internal listening port | Random high port between 10000-60000 |
| WebSocket Path | Nginx forwarding path | `/login` |
| Email | Let's Encrypt certificate notification email | - |

After confirmation, the script automatically executes 6 steps:

1. Install V2Ray
2. Configure V2Ray (vmess + WebSocket)
3. Install Nginx and deploy a camouflage website
4. Configure Nginx reverse proxy (HTTP + WS forwarding)
5. Configure firewall (allow ports 80, 443, and the V2Ray port)
6. Request and install TLS certificate via certbot (with auto-renewal)

Upon completion, the full client connection parameters are displayed.

### change-domain Workflow

Used when switching to a new domain (e.g. domain expiry). Only requires the new domain and email:

1. Automatically reads existing V2Ray configuration (UUID / port / path remain unchanged)
2. Rewrites Nginx configuration
3. Re-issues TLS certificate
4. Outputs the updated full configuration

### Client Configuration

The `info` command outputs the following client parameters — enter them directly into your V2Ray client:

| Parameter | Value |
|-----------|-------|
| Address | Your domain |
| Port | 443 |
| User ID (id) | Your UUID |
| Alter ID (alterId) | 0 |
| Security | auto |
| Network | ws |
| Path | Your WebSocket path |
| TLS | tls |

---

## godaddy-dns.sh

Manage domain DNS records via the GoDaddy API — supports listing, creating, updating, and deleting records.

### Prerequisites

- A GoDaddy account with your domain hosted on GoDaddy
- API Key + Secret (obtain at https://developer.godaddy.com/keys)

### Commands

```bash
# Configure API credentials (persisted to ~/.godaddy-dns.conf)
bash godaddy-dns.sh config

# List DNS records
bash godaddy-dns.sh list -d example.com
bash godaddy-dns.sh list -d example.com -t A        # A records only

# Create or update a record (interactive mode, auto-detects create/update)
bash godaddy-dns.sh set

# Create or update a record (non-interactive mode)
bash godaddy-dns.sh set -d example.com -n dev -t A -v 1.2.3.4
bash godaddy-dns.sh set -d example.com -n www -t CNAME -v other.com

# Delete a record
bash godaddy-dns.sh delete -d example.com -n old -t A
```

### Parameters

| Parameter | Short | Description | Default |
|-----------|-------|-------------|---------|
| `--domain` | `-d` | Primary domain | Default domain from config file |
| `--name` | `-n` | Record name (`@` = root domain, `www`, `dev`, `*`, etc.) | Interactive input |
| `--type` | `-t` | Record type (A / AAAA / CNAME / TXT / MX / NS / SRV) | A |
| `--value` | `-v` | Record value (IP address, domain, etc.) | Interactive input |
| `--ttl` | | TTL in seconds | 600 |

### Features

- **Auto create/update detection**: The `set` command checks if the record exists — updates if found, creates if not
- **Auto IP detection for A records**: When setting an A record, the script auto-detects the server's public IP — just press Enter to use it
- **Persistent credentials**: API keys are saved in `~/.godaddy-dns.conf` (permission 600) — configure once, no need to re-enter
- **Post-operation verification**: After modifications, the script queries the record to confirm the change took effect

---

## Typical Deployment Workflow

```bash
# 1. Configure GoDaddy API
bash godaddy-dns.sh config

# 2. Point domain A record to VPS
bash godaddy-dns.sh set -d example.com -n dev -t A -v <your-VPS-IP>

# 3. SSH into VPS and deploy V2Ray
bash v2ray-deploy.sh install

# 4. Switch domain after expiry
bash godaddy-dns.sh set -d newdomain.com -n dev -t A -v <your-VPS-IP>
bash v2ray-deploy.sh change-domain
```
