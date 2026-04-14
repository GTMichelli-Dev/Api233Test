#!/bin/bash
set -euo pipefail

# Usage: bash deploy/server-setup.sh [domain]
# Example: bash deploy/server-setup.sh api233test.scaledata.net

DOMAIN="${1:-api233test.scaledata.net}"

read -rp "Enter your email for Let's Encrypt certificates: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "Error: Email is required for Certbot."
    exit 1
fi
APP_DIR="/var/www/scaleapi"

echo "=== Setting up $DOMAIN ==="

# ─── Install packages ────────────────────────────────────────────────────────
apt update
apt install -y nginx certbot python3-certbot-nginx curl

# ─── Install .NET 8 runtime ──────────────────────────────────────────────────
if ! command -v dotnet &>/dev/null; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel 8.0 --runtime aspnetcore --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
fi
echo "dotnet version: $(dotnet --info | head -1)"

# ─── App directory ────────────────────────────────────────────────────────────
mkdir -p "$APP_DIR"
chown www-data:www-data "$APP_DIR"

# ─── systemd service ─────────────────────────────────────────────────────────
cp /tmp/scaleapi.service /etc/systemd/system/scaleapi.service
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

# ─── Let's Encrypt certificates ──────────────────────────────────────────────
# ECDSA cert (modern browsers)
certbot certonly --nginx \
    --non-interactive --agree-tos --email "$EMAIL" \
    -d "$DOMAIN" \
    --cert-name "${DOMAIN}-ecdsa" \
    --key-type ecdsa

# RSA cert (embedded PLC clients)
certbot certonly --nginx \
    --non-interactive --agree-tos --email "$EMAIL" \
    -d "$DOMAIN" \
    --cert-name "${DOMAIN}-rsa" \
    --key-type rsa

# ─── Apply full Nginx config with SSL ────────────────────────────────────────
cp deploy/nginx-scaleapi.conf /etc/nginx/sites-available/scaleapi
nginx -t && systemctl reload nginx

echo ""
echo "=== Setup complete ==="
echo "  Domain:  https://$DOMAIN"
echo "  App dir: $APP_DIR"
echo "  Next:    run deploy/deploy.sh to publish the app"
