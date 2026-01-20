#!/bin/bash
# --- 100% OFFLINE NETBOX INSTALLATION SCRIPT ---
set -e

# ---------------- CONFIGURATION ----------------
FQDN="rocky-08-02.vgs.com"
IPADDRESS="192.168.253.134"
NETBOX_VERSION="v4.4.9"
MIRROR_URL="https://http-server-01/repo"

DB_NAME="netbox"
DB_USER="netbox"
DB_PASS="Root@123"

NETBOX_ROOT="/opt/netbox"
PYTHON_BIN="/usr/bin/python3.12"

log() { echo -e "\e[32m✔ $1\e[0m"; }

# ---------------- CLEANUP OLD INSTALL ----------------
log "Cleaning up old installation..."
systemctl stop netbox netbox-worker nginx redis postgresql-15 || true
rm -rf $NETBOX_ROOT
# WARNING: This wipes the existing Postgres 15 data for a clean start
rm -rf /var/lib/pgsql/15/data/*

# ---------------- REPOS ----------------
log "Ensuring offline repositories are active..."
# Clear old metadata to ensure no internet calls are made
dnf clean all
dnf repolist

# ---------------- PACKAGES ----------------
log "Installing system dependencies from Offline Repo..."
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
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
ALTER SCHEMA public OWNER TO $DB_USER;
EOF

# ---------------- NETBOX SOURCE ----------------
log "Downloading NetBox Source from Mirror..."
mkdir -p $NETBOX_ROOT
# -k ignores self-signed SSL on your internal mirror
curl -kL ${MIRROR_URL}/netbox_offline_repo/src/netbox-${NETBOX_VERSION}.tar.gz -o /tmp/netbox.tar.gz
tar -xzf /tmp/netbox.tar.gz -C $NETBOX_ROOT --strip-components=1

cd $NETBOX_ROOT

# ---------------- PYTHON VENV & PKGS ----------------
log "Creating Python virtual environment..."
$PYTHON_BIN -m venv venv
source venv/bin/activate

log "Installing Python Wheels from Offline Mirror..."
# --no-index forces pip to ignore the internet
# --find-links points to your hosted .whl files
pip install --no-index --upgrade --find-links=${MIRROR_URL}/netbox_offline_repo/python_pkgs pip wheel
pip install --no-index --find-links=${MIRROR_URL}/netbox_offline_repo/python_pkgs gunicorn "psycopg[c,pool]"
pip install --no-index --find-links=${MIRROR_URL}/netbox_offline_repo/python_pkgs -r requirements.txt

# ---------------- CONFIGURATION ----------------
log "Configuring NetBox..."
SECRET_KEY=$(python3 netbox/generate_secret_key.py)
PEPPER=$(python3 netbox/generate_secret_key.py)

cat <<EOF > netbox/netbox/configuration.py
import os
ALLOWED_HOSTS = ['$FQDN','$IPADDRESS']
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
WorkingDirectory=$NETBOX_ROOT/netbox
ExecStart=$NETBOX_ROOT/venv/bin/gunicorn --bind 127.0.0.1:8001 --workers 3 netbox.wsgi
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
log "Configuring Nginx..."
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
    location /static/ { alias $NETBOX_ROOT/netbox/static/; }
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# ---------------- START ----------------
systemctl daemon-reload
systemctl enable --now netbox netbox-worker nginx postgresql-15 redis
firewall-cmd --permanent --add-service={http,https}
firewall-cmd --reload || true

log "DONE! Access at https://$IPADDRESS (User: netadmin / Pass: Netbox12345678)"
