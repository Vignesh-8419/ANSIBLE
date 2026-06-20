#!/bin/bash

# =============================================================================
# Rocky 8 HTTP Repository Server Setup
# =============================================================================

set -e

DEFAULT_GW="192.168.253.2"
REPO_DIR="/var/www/html/repo"
CIFS_SHARE="//192.168.31.87/ISO"
CIFS_OPTS="username=vigne,password=Vigneshv12$,rw,dir_mode=0777,file_mode=0777,vers=3.0"

echo "====================================================="
echo " Rocky 8 HTTP Repository Server Setup"
echo "====================================================="

# -----------------------------------------------------------------------------
# Ensure Default Gateway Exists
# -----------------------------------------------------------------------------

echo "[PRE-TASK] Checking default gateway..."

if ! ip route show | grep -q '^default'; then
    echo "Default gateway missing. Adding ${DEFAULT_GW}..."
    ip route add default via "${DEFAULT_GW}"
else
    echo "Default gateway already configured."
fi

# -----------------------------------------------------------------------------
# Install Python 3.9
# -----------------------------------------------------------------------------

echo "[TASK] Checking Python 3.9..."

if ! command -v python3.9 >/dev/null 2>&1; then
    echo "Installing Python 3.9..."
    dnf install -y python39
else
    echo "Python 3.9 already installed."
fi

# -----------------------------------------------------------------------------
# Install Required Packages
# -----------------------------------------------------------------------------

echo "[TASK] Installing required packages..."

dnf install -y \
    httpd \
    createrepo \
    firewalld \
    openssl \
    cifs-utils

# -----------------------------------------------------------------------------
# Create Repository Directory
# -----------------------------------------------------------------------------

echo "[TASK] Creating repository directory..."

mkdir -p "${REPO_DIR}"
chmod 0777 "${REPO_DIR}"

# -----------------------------------------------------------------------------
# Mount CIFS Share
# -----------------------------------------------------------------------------

echo "[TASK] Mounting CIFS share..."

if ! mountpoint -q "${REPO_DIR}"; then
    mount -t cifs "${CIFS_SHARE}" "${REPO_DIR}" -o "${CIFS_OPTS}"
else
    echo "CIFS share already mounted."
fi

# Persist mount in /etc/fstab
if ! grep -q "${CIFS_SHARE}" /etc/fstab; then
    echo "${CIFS_SHARE} ${REPO_DIR} cifs ${CIFS_OPTS} 0 0" >> /etc/fstab
fi

# -----------------------------------------------------------------------------
# Configure Firewalld
# -----------------------------------------------------------------------------

echo "[TASK] Configuring firewalld..."

systemctl enable --now firewalld

firewall-cmd --permanent --query-service=http >/dev/null 2>&1 || \
firewall-cmd --permanent --add-service=http

firewall-cmd --reload

# -----------------------------------------------------------------------------
# Remove HTTPS Redirect Configuration
# -----------------------------------------------------------------------------

echo "[TASK] Removing SSL redirect configuration..."

rm -f /etc/httpd/conf.d/ssl-redirect.conf
rm -f /etc/httpd/conf.d/ssl.conf

# -----------------------------------------------------------------------------
# Configure Apache Access
# -----------------------------------------------------------------------------

echo "[TASK] Configuring Apache..."

if ! grep -q "ANSIBLE MANAGED BLOCK - /var/www/html access" /etc/httpd/conf/httpd.conf; then

cat <<'EOF' >> /etc/httpd/conf/httpd.conf

# BEGIN ANSIBLE MANAGED BLOCK - /var/www/html access
<Directory "/var/www/html">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
# END ANSIBLE MANAGED BLOCK - /var/www/html access

EOF

fi

# -----------------------------------------------------------------------------
# Start Apache
# -----------------------------------------------------------------------------

echo "[TASK] Starting Apache..."

systemctl enable httpd
systemctl restart httpd

# -----------------------------------------------------------------------------
# Verify Apache Configuration
# -----------------------------------------------------------------------------

echo "[VERIFY] Apache configuration..."

apachectl configtest

# -----------------------------------------------------------------------------
# Verify Repository Access
# -----------------------------------------------------------------------------

echo "[VERIFY] Testing local repository access..."

HTTP_RESPONSE=$(curl -sI http://127.0.0.1/repo/)

echo "${HTTP_RESPONSE}"

if echo "${HTTP_RESPONSE}" | grep -q "200"; then
    echo
    echo "SUCCESS -> HTTP repository is accessible."
else
    echo
    echo "FAILED -> HTTP repository is not accessible."
    exit 1
fi

echo
echo "====================================================="
echo " Repository Server Configuration Completed"
echo "====================================================="
