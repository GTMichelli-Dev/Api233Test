#!/bin/bash
set -euo pipefail

# Usage: ./deploy/deploy.sh [user@host]
# First run:  ./deploy/deploy.sh admin@<vultr-ip>
# After that: ./deploy/deploy.sh  (uses saved target)

TARGET_FILE=".deploy-target"
APP_DIR="/var/www/scaleapi"

if [ -n "${1:-}" ]; then
    TARGET="$1"
    echo "$TARGET" > "$TARGET_FILE"
else
    if [ ! -f "$TARGET_FILE" ]; then
        echo "Usage: $0 <user@host>"
        echo "First run requires the target server."
        exit 1
    fi
    TARGET=$(cat "$TARGET_FILE")
fi

echo "=== Deploying to $TARGET ==="

# ─── Build ────────────────────────────────────────────────────────────────────
echo "Building..."
dotnet publish -c Release -o ./publish

# ─── Push ─────────────────────────────────────────────────────────────────────
echo "Uploading to $TARGET:$APP_DIR ..."
rsync -az --delete ./publish/ "$TARGET:$APP_DIR/"

# ─── Restart ──────────────────────────────────────────────────────────────────
echo "Restarting service..."
ssh "$TARGET" "systemctl restart scaleapi"

echo "=== Deploy complete ==="
