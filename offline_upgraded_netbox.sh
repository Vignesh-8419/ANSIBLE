=#!/bin/bash
set -e

# ---------------- CONFIGURATION ----------------
FQDN="rocky-08-02.vgs.com"
IPADDRESS="192.168.253.134"
REPO_SERVER="192.168.253.136"
NETBOX_VERSION="v4.4.9"

DB_NAME="netbox"
DB_USER="netbox"
DB_PASS="Root@123"

NETBOX_ROOT="/opt/netbox"
PYTHON_BIN="/usr/bin/python3.12"

# ---------------- FUNCTIONS ----------------
log() { echo -e "\e[32m✔ $1\e[0m"; }

# ---------------- REPO SETUP ----------------
log "Configuring local repositories..."
rm -rf /etc/yum.repos.d/*

cat <<EOF > /etc/yum.repos.d/internal_mirror.repo
[rocky8-baseos]
name=Rocky Linux 8 BaseOS
baseurl=https://${REPO_SERVER}/repo/rocky8/BaseOS
enabled=1
gpgcheck=0
sslverify=0

[rocky8-appstream]
name=Rocky Linux 8 AppStream
baseurl=https://${REPO_SERVER}/repo/rocky8/Appstream
enabled=1
gpgcheck=0
sslverify=0

[netbox-offline]
name=NetBox Offline Repository
baseurl=https://${REPO_SERVER}/repo/netbox_offline_repo/rpms
enabled=1
gpgcheck=0
sslverify=0
priority=1

[local-packages]
name=Local Core Dependencies
baseurl=https://${REPO_SERVER}/repo/ansible_offline_repo/packages
enabled=1
gpgcheck=0
sslverify=0
EOF

# ---------------- CLEANUP ----------------
log "Cleaning up old services and files..."
systemctl stop netbox netbox-worker nginx redis postgresql-15 postgresql || true
pkill -9 -f gunicorn || true
rm -rf $NETBOX_ROOT

# ---------------- PACKAGES ----------------
log "Installing system dependencies..."
dnf clean all
dnf install -y \
  python3.12 python3.12-devel python3.12-pip \
  gcc openssl-devel libffi-devel libxml2-devel libxslt-devel \
  libjpeg-turbo-devel zlib-devel \
  redis nginx openssl \
  postgresql15-server postgresql15-devel tar

export PATH=$PATH:/usr/pgsql-15/bin

# ---------------- DATABASE ----------------
log "Initializing PostgreSQL 15..."
[ ! -d "/var/lib/pgsql/15/data/base" ] && /usr/pgsql-15/bin/postgresql-15-setup initdb
systemctl enable --now postgresql-15 redis

log "Creating NetBox database..."
cd /tmp
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
ALTER SCHEMA public OWNER TO $DB_USER;
EOF
cd ~

# ---------------- NETBOX SOURCE ----------------
log "Downloading NetBox source..."
mkdir -p $NETBOX_ROOT
curl -kL https://${REPO_SERVER}/repo/netbox_offline_repo/src/netbox-${NETBOX_VERSION}.tar.gz -o /tmp/netbox.tar.gz
tar -xzf /tmp/netbox.tar.gz -C $NETBOX_ROOT --strip-components=1

# ---------------- PYTHON VENV ----------------
log "Creating Python virtual environment..."
cd $NETBOX_ROOT
$PYTHON_BIN -m venv venv
source venv/bin/activate

log "Installing base Python tools..."
pip install --no-index --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} pip wheel setuptools gunicorn psycopg psycopg_pool

# ---------------- MANUAL INJECTION (THE FIX) ----------------
log "Manually extracting legacy packages..."
SITEPKGS="$NETBOX_ROOT/venv/lib/python3.12/site-packages"

# Helper function to download and extract safely
inject_pkg() {
    local name=$1
    local file=$2
    local target_dir=$3
    log "Injecting $name..."
    mkdir -p "/tmp/manual_$name"
    curl -kL "https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs/$file" -o "/tmp/$file"
    
    # Check if download was actually successful (not a 404 page)
    if ! file "/tmp/$file" | grep -q "gzip compressed"; then
        echo -e "\e[31m✘ Error: $file is not a valid tarball. Check if version exists on server.\e[0m"
        exit 1
    fi
    
    tar -xzf "/tmp/$file" -C "/tmp/manual_$name" --strip-components=1
    cp -r "/tmp/manual_$name/$target_dir" "$SITEPKGS/"
}

# 1. django-pglocks
inject_pkg "pglocks" "django-pglocks-1.0.4.tar.gz" "django_pglocks"

# 2. sgmllib3k (it's a single file, not a directory)
log "Injecting sgmllib3k..."
curl -kL "https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs/sgmllib3k-1.0.0.tar.gz" -o "/tmp/sgmllib.tar.gz"
mkdir -p /tmp/manual_sgmllib && tar -xzf /tmp/sgmllib.tar.gz -C /tmp/manual_sgmllib --strip-components=1
cp /tmp/manual_sgmllib/sgmllib.py "$SITEPKGS/"

# 3. promise
inject_pkg "promise" "promise-2.3.tar.gz" "promise"

# 4. six (Try 1.16.0 as it is the most common version in offline repos)
# If this fails, please check the exact filename at https://192.168.253.136/repo/netbox_offline_repo/python_pkgs/
inject_pkg "six" "six-1.16.0.tar.gz" "six.py" || inject_pkg "six" "six-1.17.0.tar.gz" "six.py"

# Verify
$NETBOX_ROOT/venv/bin/python3 -c "import django_pglocks, sgmllib, promise, six; print('✔ All manual injections verified')"

# ---------------- FINALIZE INSTALL ----------------
log "Installing remaining requirements..."
sed -i '/django-pglocks/d; /sgmllib3k/d; /psycopg/d; /promise/d; /six/d' requirements.txt

pip install --no-index --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} -r requirements.txt

log "Configuring NetBox..."
SECRET_KEY=$(venv/bin/python3 netbox/generate_secret_key.py)
cat <<EOF > netbox/netbox/configuration.py
import os
ALLOWED_HOSTS = ['*']
DATABASE = {'NAME': '$DB_NAME','USER': '$DB_USER','PASSWORD': '$DB_PASS','HOST': '127.0.0.1'}
REDIS = {'tasks': {'HOST': '127.0.0.1', 'PORT': 6379, 'DATABASE': 0}, 'caching': {'HOST': '127.0.0.1', 'PORT': 6379, 'DATABASE': 1}}
SECRET_KEY = '$SECRET_KEY'
EOF

log "Running migrations..."
venv/bin/python3 netbox/manage.py migrate
venv/bin/python3 netbox/manage.py collectstatic --noinput

log "INSTALL COMPLETE"
