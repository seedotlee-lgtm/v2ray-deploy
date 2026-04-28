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

# Full deployment with auto GoDaddy DNS setup (A + AAAA records)
bash v2ray-deploy.sh full

# Add IPv6 support to an existing IPv4-only domain
bash v2ray-deploy.sh add-ipv6

# Add a brand-new IPv6-only domain (reuses the existing V2Ray service)
bash v2ray-deploy.sh add-ipv6-only

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

After confirmation, the script automatically executes 7 steps:

1. Install V2Ray
2. Configure V2Ray (vmess + WebSocket)
3. Install Nginx and deploy a camouflage website
4. Configure Nginx reverse proxy (HTTP + WS forwarding, **dual-stack IPv4 + IPv6 by default**)
5. Configure firewall (allow ports 80, 443, and the V2Ray port; auto-enables UFW IPv6)
6. Request and install TLS certificate via certbot (with auto-renewal)
7. Generate client config files (Clash Verge + Shadowrocket + VMess link)

Upon completion, the full client connection parameters are displayed.

> The Nginx config includes `listen 80; listen [::]:80;` by default. certbot automatically adds the matching `listen 443 ssl; listen [::]:443 ssl;` — no manual tweaks required.

### add-ipv6 Workflow

Use this when the server **already has the IPv4 stack deployed** (V2Ray + Nginx + cert in place) and you want to add IPv6 support afterwards.

```bash
bash v2ray-deploy.sh add-ipv6
```

Steps performed:

1. Detect the server's public IPv6 address (errors out if none)
2. Auto-read the deployed domain from nginx (override interactively if needed)
3. **Patch the Nginx config**: original config is backed up to `*.bak.YYYYMMDDHHMMSS`; `sed` inserts a `listen [::]:PORT;` line after every `listen PORT;` line, including the `listen 443 ssl;` line written by certbot
4. `nginx -t` validates and `systemctl reload nginx` applies (no restart needed)
5. **Set the AAAA DNS record**: choose GoDaddy API automation or manual; in automatic mode the script polls Google/Cloudflare DNS until the AAAA record propagates

> **No certificate re-issuance needed.** Let's Encrypt certificates are bound to the domain, not the IP — the existing cert serves both IPv4 and IPv6 transparently.

> Dual-stack listeners only help if your VPS has a publicly routable IPv6 address. Confirm in your provider's panel that IPv6 is enabled.

### add-ipv6-only Workflow

Use this when you want a **new, separate IPv6-only domain** alongside an already deployed V2Ray service — e.g. you already have `dev.example.com` (dual-stack) and now want `dev6.example.com` to serve IPv6 only.

```bash
bash v2ray-deploy.sh add-ipv6-only
```

Steps:

1. Detect the server's public IPv6 address (errors out if none)
2. **Reuse the existing V2Ray configuration** (port / UUID / WebSocket path) — `/usr/local/etc/v2ray/config.json` is **not** modified
3. Prompt for the new domain and a certbot email
4. **AAAA record is opt-in**:
   - `y` → set/update via GoDaddy API and poll Google/Cloudflare DNS until propagated
   - `n` → **skip DNS step and jump straight to cert issuance** (assumes you already configured AAAA elsewhere)
5. Create a dedicated nginx server block with `listen [::]:80;` only (no `listen 80;`) so it never responds on IPv4
6. certbot issues the cert (auto-adds `listen [::]:443 ssl;`)
7. Regenerate client config files into `client-configs/`

> **No V2Ray restart needed.** The inbound stays on `127.0.0.1:${V2RAY_PORT}`, talking to nginx via loopback only — completely decoupled from the external IP stack. Clients keep the same UUID and path, only the address changes.

> **Limitation**: an IPv6-only domain is unreachable from IPv4-only clients (some mobile carriers, corporate networks).

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
bash godaddy-dns.sh set -d example.com -n dev -t AAAA -v 2001:db8::1
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

# 5. (Optional) Add IPv6 support to an existing IPv4 domain
bash v2ray-deploy.sh add-ipv6
```

---

## IPv6 Support

The script enables Nginx dual-stack listeners (`listen 80;` + `listen [::]:80;`) by default and, in `full` mode, automatically writes both A and AAAA DNS records.

| Scenario | Command |
|----------|---------|
| Fresh deploy on a VPS with IPv6 | `bash v2ray-deploy.sh full` (writes A + AAAA) |
| Fresh deploy with self-managed DNS | `bash v2ray-deploy.sh install` + add A/AAAA records yourself |
| **Add IPv6 to an existing IPv4 domain** | `bash v2ray-deploy.sh add-ipv6` |
| **Add a separate IPv6-only domain** | `bash v2ray-deploy.sh add-ipv6-only` |

**Verify IPv6 is working:**

```bash
# Server side: confirm nginx is listening on IPv6
ss -tlnp | grep -E ':80|:443'        # expect :::80 and :::443

# DNS: AAAA propagation
dig AAAA your-domain.com @8.8.8.8
dig AAAA your-domain.com @1.1.1.1

# Client: force IPv6 to confirm reachability
curl -6 -v https://your-domain.com
```

> **Note:** Dual-stack support only works if your VPS has a publicly routable IPv6 address. Vultr / DigitalOcean and other major providers ship IPv6 by default — confirm it's enabled in the control panel.
