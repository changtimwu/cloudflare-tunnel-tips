# Cloudflare Tunnel Concepts

## Quick: Expose a Local Port for a Demo

Use `add-route.sh` to add a new public hostname to the `mymbpr` tunnel in one command:

```bash
# One-time: set your API token in ~/.zshrc
export CLOUDFLARE_API_TOKEN=your_token_here   # dash.cloudflare.com/profile/api-tokens → "Edit Cloudflare Tunnel" template

# Expose localhost:3000 at https://mymbpr-demo.wormhole.work
./add-route.sh mymbpr-demo 3000
```

The script reads the current remote config, appends the new route, pushes it back via the Cloudflare API, and creates the DNS CNAME. The running `cloudflared` daemon picks it up immediately — no restart needed.

### Why not the Cloudflare MCP for Claude Code?

The [Cloudflare MCP for Claude Code](https://developers.cloudflare.com/agent-setup/claude-code/) is focused on **developer platform products** — Workers, KV, R2, D1, Hyperdrive. It has no tools for Cloudflare Tunnel management. The only way to automate tunnel routes from Claude Code is to call the Cloudflare REST API directly, which is what `add-route.sh` does.

---

## Mental Model

```
Domain (wormhole.work)
└── Tunnel (mymbpr) — represents ONE physical machine
    ├── mymbpr-simple.wormhole.work → localhost:3000
    ├── mymbpr-ssh.wormhole.work    → localhost:22
    └── mymbpr-api.wormhole.work    → localhost:8080
```

**Domain** — `wormhole.work` lives in Cloudflare DNS. One domain can have many tunnels attached to it, each representing a different machine on a different intranet.

**Tunnel** — a persistent encrypted connection from one physical machine to Cloudflare's edge, maintained by the `cloudflared` daemon. The tunnel name (e.g. `mymbpr`) is just a label for the machine — it has nothing to do with subdomain names.

**Public Hostname (route)** — maps a subdomain to a local port on that machine. Add as many as you want per tunnel. Cloudflare automatically issues and renews HTTPS certificates for each one.

> Subdomains must be one level deep (e.g. `mymbpr-simple.wormhole.work`) to be covered by
> Cloudflare's free Universal SSL wildcard (`*.wormhole.work`). Third-level subdomains like
> `simple.mymbpr.wormhole.work` are not covered and will cause `ERR_SSL_VERSION_OR_CIPHER_MISMATCH`.

---

## What Each Piece Does

| Thing | Where it lives | What it does |
|---|---|---|
| `cloudflared` daemon | Your machine | Keeps the tunnel connection alive |
| Tunnel credential JSON | `~/.cloudflared/<tunnel-id>.json` | Authenticates your machine to Cloudflare |
| Public Hostname config | Cloudflare Zero Trust dashboard | Maps subdomain → local port |
| DNS CNAME record | Cloudflare DNS | Points the subdomain at the tunnel |

The dashboard config and DNS CNAME are created together when you add a public hostname — you don't manage them separately.

---

## Setup Steps for a New App

1. Make sure `cloudflared` is running: `cloudflared tunnel run mymbpr`
2. Go to [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com) → **Networks → Tunnels → mymbpr → Configure**
3. **Public Hostnames** tab → **Add a public hostname**
   - Subdomain: `mymbpr-simple`
   - Domain: `wormhole.work`
   - Service Type: `HTTP`
   - URL: `localhost:3000`
4. Save — Cloudflare creates the DNS CNAME and issues the HTTPS cert automatically. The running `cloudflared` picks up the new route immediately, no restart needed.

---

## Local config.yml vs Dashboard (Remote) Config

Cloudflare Tunnels support two ingress management modes:

**Locally-managed** — ingress rules live in `~/.cloudflared/config.yml`. Works when the tunnel has never been configured via the dashboard.

**Remotely-managed** — ingress rules are configured in the Zero Trust dashboard and pushed to `cloudflared` at runtime. The dashboard config overrides any local `ingress:` rules in config.yml.

Once a tunnel is remotely-managed, use the dashboard to add/remove routes. This is the better approach for a persistent machine with multiple apps — you can change routes without restarting `cloudflared`.

---

## Current Setup

### mymbpr tunnel (this MacBook)

Tunnel ID: `3e3ddd46-93d1-4c68-bbaf-e04085c1bede`
Credentials: `~/.cloudflared/3e3ddd46-93d1-4c68-bbaf-e04085c1bede.json`
Config: `~/.cloudflared/config.yml`

| Subdomain | Local service |
|---|---|
| `mymbpr-simple.wormhole.work` | `http://localhost:3000` |
| `ssh.mymbpr.wormhole.work` | `ssh://localhost:22` |

Run: `cloudflared tunnel run mymbpr`

### timhometest tunnel (home machine)

Tunnel ID: `21e2a22a-1eff-4fe7-bfeb-16dd2c684411`

Active — running on a separate machine, managed independently.

---

## Useful Commands

```bash
# List all tunnels
cloudflared tunnel list

# Tunnel details and active connections
cloudflared tunnel info mymbpr

# Start a tunnel (reads ~/.cloudflared/config.yml)
cloudflared tunnel run mymbpr
```
