#!/bin/bash
set -euo pipefail

# Usage: sudo bash server-setup.sh <vultr-ip>
# Example: sudo bash server-setup.sh 207.148.13.214

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo -E bash "$0" "$@"
fi

VULTR_IP="${1:?Usage: $0 <vultr-ip>}"
DOMAIN="zm233apitest.scaledata.net"
APP_DIR="/var/www/scaleapi"
REPO="https://github.com/GTMichelli-Dev/Api233Test.git"

# Resolve the invoking user's home (falls back to root's home when run directly as root).
INVOKING_USER="${SUDO_USER:-$USER}"
INVOKING_HOME="$(getent passwd "$INVOKING_USER" | cut -d: -f6)"
INVOKING_HOME="${INVOKING_HOME:-$HOME}"
REPO_DIR="$INVOKING_HOME/Api233Test"

# If this script is being run from inside an existing checkout, use that instead.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../ScaleApi.csproj" ]; then
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

read -rp "Enter your email for Let's Encrypt certificates: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "Error: Email is required for Certbot."
    exit 1
fi

echo "=== Setting up $DOMAIN on $VULTR_IP ==="

# ─── Install packages ────────────────────────────────────────────────────────
apt update
apt install -y git nginx certbot python3-certbot-nginx curl

# ─── Clone the repo ──────────────────────────────────────────────────────────
if [ ! -d "$REPO_DIR" ]; then
    git clone "$REPO" "$REPO_DIR"
fi
cd "$REPO_DIR"

# ─── Install .NET 8 SDK ─────────────────────────────────────────────────────
if ! command -v dotnet &>/dev/null; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
fi
echo "dotnet: $(dotnet --version)"

# ─── App directory ────────────────────────────────────────────────────────────
mkdir -p "$APP_DIR"
chown www-data:www-data "$APP_DIR"

# ─── systemd service ─────────────────────────────────────────────────────────
cp deploy/scaleapi.service /etc/systemd/system/scaleapi.service
systemctl daemon-reload
systemctl enable scaleapi

# ─── Nginx config ─────────────────────────────────────────────────────────────
cp deploy/nginx-scaleapi.conf /etc/nginx/sites-available/scaleapi
ln -sf /etc/nginx/sites-available/scaleapi /etc/nginx/sites-enabled/scaleapi
rm -f /etc/nginx/sites-enabled/default

# Temporarily use a simple HTTP config for cert issuance
cat > /etc/nginx/sites-available/scaleapi <<TMPCONF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://localhost:5000;
    }
}
TMPCONF

nginx -t && systemctl restart nginx

# ─── Firewall ────────────────────────────────────────────────────────────────
ufw allow 80
ufw allow 443
ufw allow 22
echo "y" | ufw enable || true
ufw reload

# ─── Let's Encrypt certificates ──────────────────────────────────────────────
# ECDSA cert (modern browsers + mbedTLS embedded clients)
# Force P-256 (secp256r1) — a NIST curve supported by mbedTLS.
# Certbot's default curve varies by version and can land on one that
# mbedTLS rejects with "Elliptic curve is unsupported".
certbot certonly --nginx \
    --non-interactive --agree-tos --email "$EMAIL" \
    -d "$DOMAIN" \
    --cert-name "${DOMAIN}-ecdsa" \
    --key-type ecdsa \
    --elliptic-curve secp256r1

# RSA cert (embedded PLC clients)
certbot certonly --nginx \
    --non-interactive --agree-tos --email "$EMAIL" \
    -d "$DOMAIN" \
    --cert-name "${DOMAIN}-rsa" \
    --key-type rsa

# ─── Apply full Nginx config with SSL ────────────────────────────────────────
cp deploy/nginx-scaleapi.conf /etc/nginx/sites-available/scaleapi
nginx -t && systemctl reload nginx

# ─── Build and publish ───────────────────────────────────────────────────────
dotnet publish -c Release -o "$APP_DIR"

# ─── Start the service ───────────────────────────────────────────────────────
systemctl restart scaleapi

echo ""
echo "=== Setup complete ==="
echo "  Domain:    https://$DOMAIN"
echo "  Server IP: $VULTR_IP"
echo "  App dir:   $APP_DIR"
echo "  Service:   systemctl status scaleapi"
echo ""
echo "For future deploys from your dev machine:"
echo "  ./deploy/deploy.sh admin@$VULTR_IP"
