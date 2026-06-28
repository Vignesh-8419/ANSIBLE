#!/bin/bash
#
# ============================================================================
# Foreman / Katello Asset Self-Healing Script
# Fixes missing Bastion UI assets
# Compatible with Foreman 3.2 / Katello 4.4
# ============================================================================

set -e

ASSET_DST="/var/lib/foreman/public/assets"

KATELLO_VERSION=$(ls -d /opt/theforeman/tfm/root/usr/share/gems/gems/katello-* 2>/dev/null | head -1)

if [ -z "$KATELLO_VERSION" ]; then
    echo "ERROR: Katello installation not found."
    exit 1
fi

ASSET_SRC="$KATELLO_VERSION/public/assets"

echo
echo "========================================="
echo " Foreman Asset Repair Utility"
echo "========================================="
echo

echo "Katello Assets:"
echo "  $ASSET_SRC"
echo

if [ ! -d "$ASSET_SRC/bastion" ]; then
    echo "ERROR: Bastion assets not found."
    exit 1
fi

if [ ! -d "$ASSET_SRC/bastion_katello" ]; then
    echo "ERROR: Bastion Katello assets not found."
    exit 1
fi

mkdir -p "$ASSET_DST"

echo
echo "Removing broken asset directories..."

rm -rf "$ASSET_DST/bastion"
rm -rf "$ASSET_DST/bastion_katello"

echo
echo "Creating symbolic links..."

ln -s "$ASSET_SRC/bastion" "$ASSET_DST/bastion"
ln -s "$ASSET_SRC/bastion_katello" "$ASSET_DST/bastion_katello"

echo
echo "Restoring SELinux labels..."

if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF "$ASSET_DST" || true
fi

echo
echo "Restarting Apache..."

systemctl restart httpd

echo
echo "Testing asset..."

HOSTNAME_FQDN=$(hostname -f)

URL="https://${HOSTNAME_FQDN}/assets/bastion/$(basename "$ASSET_SRC"/bastion/bastion-*.js)"

STATUS=$(curl -ks -o /dev/null -w "%{http_code}" "$URL")

echo
echo "HTTP Status : $STATUS"

if [ "$STATUS" = "200" ]; then
    echo
    echo "========================================="
    echo " SUCCESS"
    echo "========================================="
    echo
    echo "Foreman/Katello assets are healthy."
else
    echo
    echo "========================================="
    echo " WARNING"
    echo "========================================="
    echo
    echo "Assets restored, but HTTP test returned:"
    echo "$STATUS"
fi

echo
echo "Done."
