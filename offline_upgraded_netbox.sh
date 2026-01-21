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

# ---------------- SYSTEM PACKAGES ----------------
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

# ---------------- MANUAL INJECTIONS (The "Shim" Fix) ----------------
log "Manually injecting legacy packages and creating Metadata Shims..."
SITEPKGS="$NETBOX_ROOT/venv/lib/python3.12/site-packages"

# 1. Install 'six' wheel
pip install --no-index --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} six

# 2. Inject django-pglocks
mkdir -p /tmp/manual_pglocks
curl -kL "https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs/django-pglocks-1.0.4.tar.gz" -o /tmp/pglocks.tar.gz
tar -xzf /tmp/pglocks.tar.gz -C /tmp/manual_pglocks --strip-components=1
cp -r /tmp/manual_pglocks/django_pglocks "$SITEPKGS/"

# 3. Inject sgmllib3k + Metadata Shim
mkdir -p /tmp/manual_sgmllib
curl -kL "https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs/sgmllib3k-1.0.0.tar.gz" -o /tmp/sgmllib.tar.gz
tar -xzf /tmp/sgmllib.tar.gz -C /tmp/manual_sgmllib --strip-components=1
cp /tmp/manual_sgmllib/sgmllib.py "$SITEPKGS/"
mkdir -p "$SITEPKGS/sgmllib3k-1.0.0.dist-info"
echo -e "Metadata-Version: 2.1\nName: sgmllib3k\nVersion: 1.0.0" > "$SITEPKGS/sgmllib3k-1.0.0.dist-info/METADATA"

# 4. Inject promise + Metadata Shim (Prevents building metadata error)
mkdir -p /tmp/manual_promise
curl -kL "https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs/promise-2.3.tar.gz" -o /tmp/promise.tar.gz
tar -xzf /tmp/promise.tar.gz -C /tmp/manual_promise --strip-components=1
cp -r /tmp/manual_promise/promise "$SITEPKGS/"
mkdir -p "$SITEPKGS/promise-2.3.dist-info"
echo -e "Metadata-Version: 2.1\nName: promise\nVersion: 2.3" > "$SITEPKGS/promise-2.3.dist-info/METADATA"

# Verify all are present
$NETBOX_ROOT/venv/bin/python3 -c "import django_pglocks, sgmllib, promise, six; print('✔ All manual injections verified')"

# ---------------- FINALIZE REQUIREMENTS ----------------
log "Installing remaining requirements..."
# Remove handled packages from requirements.txt to avoid pip trying to re-fetch them
sed -i '/django-pglocks/d; /sgmllib3k/d; /psycopg/d; /promise/d; /six/d' requirements.txt

pip install --no-index --find-links=https://${REPO_SERVER}/repo/netbox_offline_repo/python_pkgs \
    --trusted-host ${REPO_SERVER} -r requirements.txt

# ---------------- CONFIGURATION ----------------
log "Configuring NetBox..."
SECRET_KEY=$(venv/bin/python3 netbox/generate_secret_key.py)

cat <<EOF > netbox/netbox/configuration.py
import os
ALLOWED_HOSTS = ['*']
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
EOF

# ---------------- MIGRATIONS ----------------
log "Running migrations and static collection..."
redis-cli -n 0 flushdb
redis-cli -n 1 flushdb
venv/bin/python3 netbox/manage.py migrate
venv/bin/python3 netbox/manage.py collectstatic --noinput

# ---------------- ADMIN USER ----------------
log "Creating admin user..."
echo "from django.contrib.auth import get_user_model; User=get_user_model(); User.objects.create_superuser('netadmin','admin@example.com','Netbox12345678')" | venv/bin/python3 netbox/manage.py shell

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

# ---------------- NGINX ----------------
log "Configuring Nginx..."
cat <<EOF > /etc/nginx/conf.d/netbox.conf
server {
    listen 80;
    server_name $FQDN;
    location /static/ {
        alias $NETBOX_ROOT/netbox/static/;
    }
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# ---------------- START ----------------
log "Starting services..."
systemctl daemon-reload
systemctl enable --now netbox netbox-worker nginx
firewall-cmd --permanent --add-service=http
firewall-cmd --reload || true

# Backup the original config
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

# Use sed to remove the default server block (everything from 'server {' to the next '} }')
# Or simply use this command to replace the file with a clean version that only loads conf.d
cat <<EOF > /etc/nginx/nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    include /etc/nginx/conf.d/*.conf;
}
EOF

systemctl restart nginx

curl -I http://192.168.253.134

log "----------------------------------------"
log "NETBOX OFFLINE INSTALL COMPLETE"
log "URL: http://$IPADDRESS"
log "----------------------------------------"
