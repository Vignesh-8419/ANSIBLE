#!/bin/bash

# =============================================================================
# Rocky 8 HTTP Repository Server Setup
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DEFAULT_GW="192.168.253.2"
REPO_DIR="/var/www/html/repo"
CIFS_SHARE="//192.168.31.87/ISO"
CIFS_OPTS="username=vigne,password=Vigneshv12$,rw,dir_mode=0777,file_mode=0777,vers=3.0"

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
success() { echo -e "${GREEN}[ OK ]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; }

echo -e "${CYAN}"
echo "====================================================="
echo " Rocky 8 HTTP Repository Server Setup"
echo "====================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Ensure Default Gateway Exists
# -----------------------------------------------------------------------------

info "Checking default gateway..."

if ! ip route show | grep -q '^default'; then
    warn "Default gateway missing. Adding ${DEFAULT_GW}..."
    ip route add default via "${DEFAULT_GW}"
    success "Default gateway added."
else
    success "Default gateway already configured."
fi

# -----------------------------------------------------------------------------
# Install Python 3.9
# -----------------------------------------------------------------------------

info "Checking Python 3.9..."

if ! command -v python3.9 >/dev/null 2>&1; then
    warn "Installing Python 3.9..."
    dnf install -y python39
    success "Python 3.9 installed."
else
    success "Python 3.9 already installed."
fi

# -----------------------------------------------------------------------------
# Install Required Packages
# -----------------------------------------------------------------------------

info "Installing required packages..."

dnf install -y \
    httpd \
    createrepo \
    firewalld \
    openssl \
    cifs-utils \
    sshpass

success "Required packages installed."

# -----------------------------------------------------------------------------
# Create Repository Directory
# -----------------------------------------------------------------------------

info "Creating repository directory..."

mkdir -p "${REPO_DIR}"
chmod 0777 "${REPO_DIR}"

success "Repository directory ready."

# -----------------------------------------------------------------------------
# Mount CIFS Share
# -----------------------------------------------------------------------------

info "Checking CIFS mount..."

if ! mountpoint -q "${REPO_DIR}"; then
    warn "Mounting CIFS share..."
    mount -t cifs "${CIFS_SHARE}" "${REPO_DIR}" -o "${CIFS_OPTS}"
    success "CIFS share mounted."
else
    success "CIFS share already mounted."
fi

if ! grep -q "${CIFS_SHARE}" /etc/fstab; then
    echo "${CIFS_SHARE} ${REPO_DIR} cifs ${CIFS_OPTS} 0 0" >> /etc/fstab
    success "Added CIFS mount to /etc/fstab."
else
    success "CIFS entry already exists in /etc/fstab."
fi

# -----------------------------------------------------------------------------
# Configure Firewalld
# -----------------------------------------------------------------------------

info "Configuring firewalld..."

systemctl enable --now firewalld

firewall-cmd --permanent --query-service=http >/dev/null 2>&1 || \
firewall-cmd --permanent --add-service=http

firewall-cmd --reload

success "Firewall configured."

# -----------------------------------------------------------------------------
# Remove SSL Redirect Configuration
# -----------------------------------------------------------------------------

info "Removing SSL configurations..."

rm -f /etc/httpd/conf.d/ssl-redirect.conf
rm -f /etc/httpd/conf.d/ssl.conf

success "SSL configuration removed."

# -----------------------------------------------------------------------------
# Configure Apache Access
# -----------------------------------------------------------------------------

info "Configuring Apache..."

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

    success "Apache directory permissions configured."
else
    success "Apache directory permissions already configured."
fi

# -----------------------------------------------------------------------------
# Start Apache
# -----------------------------------------------------------------------------

info "Starting Apache..."

systemctl enable httpd
systemctl restart httpd

success "Apache started."

# -----------------------------------------------------------------------------
# Verify Apache Configuration
# -----------------------------------------------------------------------------

info "Running Apache configuration test..."

if apachectl configtest; then
    success "Apache configuration is valid."
else
    error "Apache configuration validation failed."
    exit 1
fi

# -----------------------------------------------------------------------------
# Verify Repository Access
# -----------------------------------------------------------------------------

info "Testing local repository access..."

HTTP_RESPONSE=$(curl -sI http://127.0.0.1/repo/)

if echo "${HTTP_RESPONSE}" | grep -q "200"; then
    success "HTTP repository is accessible."
else
    error "HTTP repository is NOT accessible."
    echo "${HTTP_RESPONSE}"
    exit 1
fi

echo
echo -e "${GREEN}"
echo "====================================================="
echo " Repository Server Configuration Completed"
echo "====================================================="
echo -e "${NC}"
