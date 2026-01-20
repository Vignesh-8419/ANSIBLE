#!/bin/bash
set -e

# ---------------- CONFIGURATION ----------------
FQDN="rocky-08-02.vgs.com"
IPADDRESS="192.168.253.134"
NETBOX_VERSION="v4.4.9"

DB_NAME="netbox"
DB_USER="netbox"
DB_PASS="Root@123"

NETBOX_ROOT="/opt/netbox"
PYTHON_BIN="/usr/bin/python3.12"

rm -rf /etc/yum.repos.d/*
cat <<EOF > /etc/yum.repos.d/internal_mirror.repo
[local-extras]
name=Local Rocky Extras
baseurl=https://http-server-01/repo/offline_repo/extras
enabled=1
gpgcheck=0
sslverify=0

[local-rancher]
name=Local Rancher K3s
baseurl=https://http-server-01/repo/offline_repo/rancher-k3s-common-stable
enabled=1
gpgcheck=0
sslverify=0

[local-packages]
name=Local Core Dependencies
baseurl=https://http-server-01/repo/offline_repo/packages
enabled=1
gpgcheck=0
sslverify=0

[netbox-offline]
name=NetBox Offline Repository
baseurl=https://http-server-01/repo/netbox_offline_repo/rpms
enabled=1
gpgcheck=0
sslverify=0
priority=1
EOF

# ---------------- FUNCTIONS ----------------
log() { echo -e "\e[32m✔ $1\e[0m"; }

# ---------------- CLEANUP ----------------
log "Stopping old services"
systemctl stop netbox netbox-worker nginx redis postgresql-15 postgresql || true
pkill -9 gunicorn || true

# ---------------- REPOS ----------------
log "Enabling EPEL & CRB"
dnf install -y epel-release dnf-plugins-core
dnf config-manager --set-enabled crb || dnf config-manager --set-enabled powertools

log "Installing PostgreSQL 15 repo"
dnf remove -y pgdg-redhat-repo || true
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql

# ---------------- PACKAGES ----------------
log "Installing system dependencies"
dnf install -y \
  python3.12 python3.12-devel python3.12-pip \
  git gcc openssl-devel libffi-devel libxml2-devel libxslt-devel \
  libjpeg-turbo-devel zlib-devel \
  redis nginx openssl \
  postgresql15-server postgresql15-devel

export PATH=$PATH:/usr/pgsql-15/bin

# ---------------- DATABASE ----------------
log "Initializing PostgreSQL"
if [ ! -d "/var/lib/pgsql/15/data/base" ]; then
  /usr/pgsql-15/bin/postgresql-15-setup initdb
fi

systemctl enable --now postgresql-15 redis

log "Creating NetBox database"
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
ALTER SCHEMA public OWNER TO $DB_USER;
EOF

# ---------------- NETBOX ----------------
log "Cloning NetBox $NETBOX_VERSION"
rm -rf $NETBOX_ROOT
git clone -b $NETBOX_VERSION --depth 1 https://github.com/netbox-community/netbox.git $NETBOX_ROOT

cd $NETBOX_ROOT

log "Creating Python virtual environment"
rm -rf venv
$PYTHON_BIN -m venv venv
source venv/bin/activate

pip install --upgrade pip wheel
pip install gunicorn "psycopg[c,pool]"
pip install -r requirements.txt

# ---------------- CONFIG ----------------
log "Configuring NetBox"
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

CSRF_TRUSTED_ORIGINS = [
    'https://$FQDN',
    'http://$FQDN',
]

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {'console': {'class': 'logging.StreamHandler'}},
    'root': {'handlers': ['console'], 'level': 'INFO'},
}
EOF

# ---------------- MIGRATIONS ----------------
log "Running migrations"
redis-cli -n 0 flushdb
redis-cli -n 1 flushdb

python3 netbox/manage.py migrate
python3 netbox/manage.py collectstatic --noinput

# ---------------- ADMIN USER ----------------
log "Creating admin user"
echo "from django.contrib.auth import get_user_model; User=get_user_model(); User.objects.create_superuser('netadmin','admin@example.com','Netbox12345678')" | python3 netbox/manage.py shell

# ---------------- SYSTEMD ----------------
log "Installing systemd services"

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
log "Configuring Nginx and SSL"
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

# ---------------- FIREWALL ----------------
systemctl enable --now firewalld || true
firewall-cmd --permanent --add-service={http,https}
firewall-cmd --reload || true

# ---------------- START SERVICES ----------------
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now netbox netbox-worker nginx

# ---------------- DONE ----------------
log "----------------------------------------"
log "NetBox CLEAN INSTALL COMPLETE"
log "URL: https://$FQDN"
log "URL: https://$IPADDRESS"
log "User: netadmin"
log "Pass: Netbox12345678"
log "----------------------------------------"
