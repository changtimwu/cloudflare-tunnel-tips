# Cloudflare Tunnel Tips

## Quick: Expose a Local Port for a Demo

Use `add-route.sh` to add a new public hostname to the `mymbpr` tunnel in one command:

```bash
# One-time: set your API token in ~/.zshrc (see screenshots below for how to create one)
export CLOUDFLARE_API_TOKEN=your_token_here

# Expose localhost:3000 at https://mymbpr-demo.wormhole.work
./add-route.sh mymbpr-demo 3000

# List current routes
./list-routes.sh

# Remove a route
./remove-route.sh mymbpr-demo
```

The scripts never hardcode account or tunnel IDs. They read everything from cloudflared's own files:

| What | Where it comes from |
|---|---|
| Tunnel name, Account ID, Tunnel ID | `~/.cloudflared/<tunnel-id>.json` (written by `cloudflared service install <token>`) |
| Domain | `.env` file alongside the scripts |
| API token | `CLOUDFLARE_API_TOKEN` env var (set in `~/.zshrc`) |

On a fresh machine, run the install command from the Cloudflare dashboard and copy the `.env` file — no IDs to look up.

### Creating the API Token

**Step 1** — Go to [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens) and click **+ Create Token**.

![Step 1 — User API Tokens page](cftun-step1.png)

**Step 2** — There is no pre-built template for Cloudflare Tunnel. Under "Custom token", click **Get started**.

![Step 2 — Select Custom Token](cftun-step2.png)

**Step 3** — Name the token (e.g. `mytunnel-token`) and set Permissions to **Account → Cloudflare Tunnel → Edit**.

![Step 3 — Configure token name and permissions](cftun-step3.png)

**Step 4** — Review the summary ("All accounts - Cloudflare Tunnel:Edit") and click **Create Token**.

![Step 4 — Confirm and create](cftun-step4.png)

Copy the token value shown on the next screen — it is only displayed once.

The script reads the current remote config, appends the new route, pushes it back via the Cloudflare API, and creates the DNS CNAME. The running `cloudflared` daemon picks it up immediately — no restart needed.

### Why not the Cloudflare MCP for Claude Code?

The [Cloudflare MCP for Claude Code](https://developers.cloudflare.com/agent-setup/claude-code/) is focused on **developer platform products** — Workers, KV, R2, D1, Hyperdrive. It has no tools for Cloudflare Tunnel management. The only way to automate tunnel routes from Claude Code is to call the Cloudflare REST API directly, which is what `add-route.sh` does.

---

## Fresh Laptop Setup

### 1. Install cloudflared

```bash
brew install cloudflared
```

### 2. Create the tunnel on the Cloudflare dashboard

Go to **[dash.cloudflare.com → Zero Trust → Networks → Tunnels](https://one.dash.cloudflare.com)** and click **+ Add a tunnel**.

Choose **Cloudflared** as the connector type, give the tunnel a name, and proceed to the **Install connector** step. Cloudflare will show a one-line install command that embeds the tunnel token, for example:

```bash
sudo cloudflared service install eyJhIjoiMTViZmUz...
```

Run that command on the host machine. It saves the tunnel credentials to `~/.cloudflared/`, writes a `config.yml`, and installs `cloudflared` as a system service that starts on boot.

> The full install command for your specific tunnel is shown in the dashboard at
> **dash.cloudflare.com → Zero Trust → Networks → Tunnels → [your tunnel] → Configure → Install connector**.

### 3. Verify the tunnel is running

```bash
cloudflared tunnel list
```

The tunnel status should show **HEALTHY** in the Zero Trust dashboard within a few seconds.

### 4. Copy the `.env` file from another machine

```bash
scp old-machine:~/cloudflare-tunnel-tips/.env ~/cloudflare-tunnel-tips/.env
```

Or create it fresh — see `.env.example` in this repo.

### Reconnecting an existing tunnel on a new machine

If the tunnel already exists (created from another machine) and you just need to run it here:

**Option A — copy credentials from the old machine:**

```bash
scp old-machine:~/.cloudflared/*.json ~/.cloudflared/
sudo cloudflared service install
```

**Option B — re-run the install command from the dashboard:**

Go to **Networks → Tunnels → [your tunnel] → Configure → Install connector** and run the shown command again. It fetches a fresh token for the same tunnel.

---

## Concepts

### Mental Model

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

### What Each Piece Does

| Thing | Where it lives | What it does |
|---|---|---|
| `cloudflared` daemon | Your machine | Keeps the tunnel connection alive |
| Tunnel credential JSON | `~/.cloudflared/<tunnel-id>.json` | Authenticates your machine to Cloudflare |
| Public Hostname config | Cloudflare Zero Trust dashboard | Maps subdomain → local port |
| DNS CNAME record | Cloudflare DNS | Points the subdomain at the tunnel |

The dashboard config and DNS CNAME are created together when you add a public hostname — you don't manage them separately.

### Local config.yml vs Dashboard (Remote) Config

Cloudflare Tunnels support two ingress management modes:

**Locally-managed** — ingress rules live in `~/.cloudflared/config.yml`. Works when the tunnel has never been configured via the dashboard.

**Remotely-managed** — ingress rules are configured in the Zero Trust dashboard and pushed to `cloudflared` at runtime. The dashboard config overrides any local `ingress:` rules in config.yml.

Once a tunnel is remotely-managed, use the dashboard to add/remove routes. This is the better approach for a persistent machine with multiple apps — you can change routes without restarting `cloudflared`.

---

## Adding a New Route via Dashboard

1. Go to [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com) → **Networks → Tunnels → mymbpr → Configure**
2. **Public Hostnames** tab → **Add a public hostname**
   - Subdomain: `mymbpr-demo`
   - Domain: `wormhole.work`
   - Service Type: `HTTP`
   - URL: `localhost:3000`
3. Save — Cloudflare creates the DNS CNAME and issues the HTTPS cert automatically. The running `cloudflared` picks up the new route immediately, no restart needed.

---

## Current Routes (mymbpr tunnel)

Tunnel ID: `3e3ddd46-93d1-4c68-bbaf-e04085c1bede`

| Subdomain | Local service |
|---|---|
| `mymbpr-simple.wormhole.work` | `http://localhost:3000` |
| `ssh.mymbpr.wormhole.work` | `ssh://localhost:22` |

---

## Useful Commands

```bash
# List all tunnels
cloudflared tunnel list

# Tunnel details and active connections
cloudflared tunnel info mymbpr

# Start the tunnel
cloudflared tunnel run mymbpr
```
