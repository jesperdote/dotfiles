#!/usr/bin/env bash
# Reproduces the system changes made on the homelab VPS ("caljerry", Ubuntu 26.04 LTS, OVH).
# Safe to re-run: every step checks current state before changing anything.
set -euo pipefail

echo "==> Installing cloudflared (Cloudflare's apt repo)"
if ! command -v cloudflared >/dev/null; then
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y cloudflared
else
    echo "    Skipped (already installed: $(cloudflared --version))"
fi

echo "==> Registering cloudflared as a systemd service"
if systemctl is-enabled cloudflared >/dev/null 2>&1; then
    echo "    Skipped (service already installed)"
else
    if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
        cat >&2 <<'EOF'
    CLOUDFLARE_TUNNEL_TOKEN is not set.

    Create the tunnel first (one-time, manual - see README.md) in the Cloudflare
    Zero Trust dashboard: Networks -> Tunnels -> Create a tunnel -> Cloudflared,
    then copy the token from the "Install connector" step it shows you. Then:

        CLOUDFLARE_TUNNEL_TOKEN=xxx ./install.sh
EOF
        exit 1
    fi
    sudo cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"
fi

echo "==> Cloning/updating proj repo (front-vps nginx proxy + placeholder backend)"
if ! command -v docker >/dev/null; then
    echo "    docker not found - install it first (already expected to be present here" >&2
    echo "    since Jenkins and the observability stack both depend on it)." >&2
    exit 1
fi
PROJ_DIR="$HOME/proj"
if [[ -d "$PROJ_DIR/.git" ]]; then
    git -C "$PROJ_DIR" pull
else
    git clone git@github.com:klept-lab/proj.git "$PROJ_DIR"
fi

echo "==> Starting front-vps (nginx reverse proxy, port 8081)"
(cd "$PROJ_DIR/front-vps" && docker compose up -d)

echo "==> Starting placeholder backend (port 8020)"
(cd "$PROJ_DIR/placeholder" && docker compose up -d)

echo "==> Done. Check status with:"
echo "        systemctl status cloudflared"
echo "        docker ps --filter name=nginx-vps --filter name=placeholder"
