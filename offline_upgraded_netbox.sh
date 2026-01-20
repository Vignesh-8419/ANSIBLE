#!/bin/bash
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
log "Configuring local repositories from $REPO_SERVER..."
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
if [ ! -d "/var/lib/pgsql/15/data/base" ]; then
  /usr/pgsql-15/bin/postgresql-15-setup initdb
fi

systemctl enable --now postgresql-15 redis

log "Creating NetBox database..."
# Move to /tmp to avoid "Permission denied" when sudo-ing to postgres user
cd /tmp
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
ALTER SCHEMA public OWNER TO $DB_USER;
EOF
cd ~

# ---------------- NETBOX SOURCE (OFFLINE) ----------------
log "Downloading NetBox source tarball from mirror..."
mkdir -p $NETBOX_ROOT
curl -kL https://${REPO_SERVER}/repo/netbox_offline_repo/src/netbox-${NETBOX_VERSION}.tar.gz -o /tmp/netbox.tar.gz
tar -xzf /tmp/netbox.tar.gz -C $NETBOX_ROOT --strip-components=1

cd $NETBOX_ROOT

# FIX: Modify requirements to use pure-python psycopg instead of seeking C-extensions
if [ -f "requirements.txt" ]; then
    sed -i 's/psycopg\[c\]/psycopg/g' requirements.txt
fi

# ---------------- PYTHON VENV & PKGS (OFFLINE) ----------------
log "Creating Python virtual environment..."
$PYTHON_BIN -m venv venv
source venv/bin/activate

log "Installing Python wheels from internal mirror..."

# 1. Upgrade pip/wheel AND install setuptools
pip install --no-index --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} pip wheel setuptools

# 2. Install database drivers and gunicorn
pip install --no-index --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} gunicorn psycopg psycopg_pool

# 3. MANUALLY install the problematic .tar.gz packages using the existing environment
# This forces it to use the setuptools we just installed.
log "Building problematic source packages..."
pip install --no-index --no-build-isolation --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} django-pglocks==1.0.4

# 4. Now install the rest of the requirements
log "Installing remaining requirements..."
pip install --no-index --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} -r requirements.txt


# ---------------- CONFIGURATION ----------------
log "Configuring NetBox..."
SECRET_KEY=$(python3 netbox/generate_secret_key.py)
PEPPER=$(python3 netbox/generate_secret_key.py)

cat <<EOF > netbox/netbox/configuration.py
import os

ALLOWED_HOSTS = ['$FQDN','$IPADDRESS']
DEBUG = False
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DATABASE = {
    'NAME': '$DB_NAME',
    'USER': '$DB_USER',
    'PASSWORD': '$DB_PASS',
    'HOST': '127.0.0.1',
    'PORT': '',
}

REDIS = {
    'tasks': {'HOST': '127.0.0.1', 'PORT': 6379, 'DATABASE': 0},
    'caching': {'HOST': '127.0.0.1', 'PORT': 6379, 'DATABASE': 1},
}

SECRET_KEY = '$SECRET_KEY'
API_TOKEN_PEPPERS = {1: '$PEPPER'}
CSRF_TRUSTED_ORIGINS = ['https://$FQDN','http://$FQDN']

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {'console': {'class': 'logging.StreamHandler'}},
    'root': {'handlers': ['console'], 'level': 'INFO'},
}
EOF

# ---------------- MIGRATIONS ----------------
log "Running migrations..."
redis-cli -n 0 flushdb
redis-cli -n 1 flushdb

python3 netbox/manage.py migrate
python3 netbox/manage.py collectstatic --noinput

# ---------------- ADMIN USER ----------------
log "Creating admin user..."
echo "from django.contrib.auth import get_user_model; User=get_user_model(); User.objects.create_superuser('netadmin','admin@example.com','Netbox12345678')" | python3 netbox/manage.py shell

# ---------------- SYSTEMD ----------------
log "Installing systemd services..."

cat <<EOF > /etc/systemd/system/netbox.service
[Unit]
Description=NetBox WSGI Service
After=network.target

[Service]
Environment="DJANGO_SETTINGS_MODULE=netbox.settings"
WorkingDirectory=$NETBOX_ROOT/netbox
ExecStart=$NETBOX_ROOT/venv/bin/gunicorn --bind 127.0.0.1:8001 --timeout 120 --workers 3 netbox.wsgi
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/netbox-worker.service
[Unit]
Description=NetBox RQ Worker
After=network.target

[Service]
WorkingDirectory=$NETBOX_ROOT/netbox
ExecStart=$NETBOX_ROOT/venv/bin/python3 manage.py rqworker
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ---------------- NGINX + SSL ----------------
log "Configuring Nginx and SSL..."
mkdir -p /etc/ssl/netbox

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/netbox/netbox.key \
  -out /etc/ssl/netbox/netbox.crt \
  -subj "/C=US/ST=State/L=City/O=IT/CN=$FQDN"

cat <<EOF > /etc/nginx/conf.d/netbox.conf
server {
    listen 80;
    server_name $FQDN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $FQDN;
    ssl_certificate /etc/ssl/netbox/netbox.crt;
    ssl_certificate_key /etc/ssl/netbox/netbox.key;

    location /static/ {
        alias $NETBOX_ROOT/netbox/static/;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# ---------------- FIREWALL & START ----------------
log "Finalizing installation..."
systemctl enable --now firewalld || true
firewall-cmd --permanent --add-service={http,https}
firewall-cmd --reload || true

systemctl daemon-reload
systemctl enable --now netbox netbox-worker nginx

log "----------------------------------------"
log "NetBox OFFLINE INSTALL COMPLETE"
log "URL: https://$IPADDRESS"
log "User: netadmin"
log "Pass: Netbox12345678"
log "----------------------------------------"
