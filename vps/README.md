# VPS setup notes ("caljerry")

Captures the system changes made on the homelab VPS, for replaying after a reinstall.
Ubuntu 26.04 LTS (OVH). Reachable via the `ssh-caljerry` alias or Tailscale
(`100.74.234.54`). Also runs the Jenkins controller and the `observability` repo's
`server/` Docker Compose stack - see that repo, not this one, for anything
Jenkins/Thanos/Grafana-related. This folder is only for things installed directly on
the host, outside that Compose stack.

## Usage

```bash
cd vps && CLOUDFLARE_TUNNEL_TOKEN=xxx ./install.sh
```

Idempotent - safe to re-run. Each step checks current state before changing anything.

## What's included

| File | Purpose |
|---|---|
| `install.sh` | Installs cloudflared, registers it as a systemd service, and brings up `proj/front-vps` + `proj/placeholder` |

Assumes Docker is already installed on this VPS (it is - both Jenkins and the
`observability` stack already depend on it), so this script doesn't install it.

## Cloudflare Tunnel: native systemd service, not a Docker container

This VPS also runs an unrelated Docker Compose stack (the `observability` repo's
`server/`, deployed by its own Jenkins pipeline). This tunnel is deliberately kept out
of that stack and installed as a native systemd service instead, via Cloudflare's own
apt repo - matching how the BananaPi (the other homelab host) already runs its
`cloudflared` tunnel. Reasons:

- Cloudflare's installer already handles the systemd unit, restart policy, and
  connection management - a Docker Compose service would just be re-implementing that
  with extra steps (e.g. `network_mode: host` to reach `localhost:<port>` targets).
- Consistency with the BananaPi's existing tunnel setup, rather than having the two
  tunnels on two hosts managed two different ways.
- This is a **remotely-managed tunnel** (`cloudflared service install <token>`) -
  ingress rules (which hostnames route to which local ports) live in the Cloudflare
  Zero Trust dashboard, not a local config file, so there's no local YAML to keep in
  sync as routes are added or removed.

This is a **second, separate tunnel** dedicated to this VPS - it does not reuse or
share anything with the BananaPi's existing tunnel/token (tunnels are 1:1 with their
`cloudflared` daemon).

## front-vps + placeholder (proj repo)

`install.sh` also clones/pulls the separate `proj` repo (`git@github.com:klept-lab/proj.git`)
to `~/proj`, creates a shared `vps-internal` Docker network, and brings up two of its
services with `docker compose up -d`:

- **`front-vps/`** - the nginx reverse proxy this tunnel points at (`localhost:8081`,
  loopback-only), the VPS-side counterpart to the BananaPi's `front/`. See
  `proj/front-vps/CLAUDE.md` for routing details.
- **`placeholder/`** - a stub `nginx:alpine-slim` backend, standing in for a real
  service until one exists. Safe to remove once `front-vps/nginx/default.conf` routes
  to something real instead.

Both are defined in `proj`, not here, since they're application-level Docker Compose
services rather than host system setup - this script just makes sure they're running.

**Security note (2026-08-19)**: `front-vps` and its backends (`placeholder`,
`infdxeta-net`) all join the `vps-internal` Docker network and communicate by container
name - none of the backends publish a host port at all, and `front-vps` itself is bound
`127.0.0.1` only. Earlier they published on `0.0.0.0` (Docker's default when no bind
address is given), which made them directly reachable from the public internet on their
raw ports, completely bypassing Cloudflare's edge - confirmed and fixed live. Any new
backend added behind `front-vps` should follow the same pattern (join `vps-internal`,
no published port) rather than reintroducing this.

## Manual steps not covered by this script

- **Creating the tunnel itself**: Cloudflare Zero Trust dashboard -> Networks ->
  Tunnels -> Create a tunnel -> Cloudflared. This produces the token `install.sh`
  needs - there's no unattended way to do this part (it's a one-time dashboard action,
  same category as Toshy's install in `cachyos/`).
- **Ingress routes / public hostnames** (e.g. routing `prN.infdxeta.info` to a local
  port for PR preview environments): configured per-route in the same dashboard, or
  eventually via the Cloudflare API once automated - not part of this script.

## Secrets

`CLOUDFLARE_TUNNEL_TOKEN` is never written to disk by this script or committed to this
repo - pass it as an environment variable at install time only.
