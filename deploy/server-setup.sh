#!/bin/bash
set -euo pipefail

# Usage: bash server-setup.sh <vultr-ip>
# Example: bash server-setup.sh 207.148.13.214

VULTR_IP="${1:?Usage: $0 <vultr-ip>}"
DOMAIN="api233test.scaledata.net"
APP_DIR="/var/www/scaleapi"
REPO="https://github.com/GTMichelli-Dev/Api233Test.git"

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
if [ ! -d ~/Api233Test ]; then
    git clone "$REPO" ~/Api233Test
fi
cd ~/Api233Test

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
