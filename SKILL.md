---
name: cf-publish
description: Expose a local port to the internet via Cloudflare Tunnel. Use when the user wants to publish, expose, share, or make public a local app, dev server, port, or localhost service (e.g. "expose port 3000", "give me a public URL for localhost:8080", "share this dev server", "make this reachable from outside"). Also handles listing and removing existing tunnel routes.
---

# Cloudflare Tunnel — Publish a local port

This skill exposes a local TCP port via an existing Cloudflare Tunnel, returning a public HTTPS URL of the form `<subdomain>.<your-domain>`.

## When to invoke

Trigger when the user wants to:
- Expose / publish / share a local port or app to the internet
- Get a public URL for a localhost service
- List, add, or remove tunnel routes

Do **not** invoke for unrelated networking tasks (firewall, VPN, port forwarding on a router).

## Prerequisites (verify before running scripts)

Run these checks. If any fail, stop and walk the user through setup using `README.md` in this skill directory.

```bash
command -v cloudflared        # cloudflared CLI installed
ls ~/.cloudflared/*.json       # at least one tunnel credentials file
test -n "$CLOUDFLARE_API_TOKEN" # token in env
test -f "$CLAUDE_SKILL_DIR/.env" # domain configured
```

The `.env` file must define `CLOUDFLARE_DOMAIN=...`. The API token needs three permissions: `Cloudflare Tunnel:Edit`, `Zone:Read`, `DNS:Edit` (see README for screenshots).

## Commands

Scripts live in this skill directory. Always invoke with the full path (set `SKILL_DIR` to the directory containing this `SKILL.md`).

**Publish a local port:**
```bash
"$SKILL_DIR/add-route.sh" <subdomain> <port>
```
Output: `https://<subdomain>.<domain> → localhost:<port>`. The route is live within seconds — no daemon restart needed.

**List current routes:**
```bash
"$SKILL_DIR/list-routes.sh"
```

**Remove a route:**
```bash
"$SKILL_DIR/remove-route.sh" <subdomain>
```

## Picking a subdomain

If the user didn't specify one, derive a name from context (project directory `basename $PWD`, the app's purpose, etc.). Lowercase, hyphens only, one level deep. **Confirm with the user before running** if you guessed.

## After publishing

Tell the user the final URL (the script prints it). On first use of a subdomain, cert issuance can take ~30s — suggest a brief wait before testing if `curl` returns SSL errors initially.

## Error handling

- `ERROR: Not logged in` → user needs `cloudflared tunnel login` or the dashboard install command.
- `ERROR: No tunnel found` → user needs to create a tunnel in the Cloudflare dashboard first.
- `ERROR: Multiple tunnels found` → set `TUNNEL_CREDS_FILE` env to disambiguate.
- DNS errors mentioning permissions → API token is missing `DNS:Edit` permission.
