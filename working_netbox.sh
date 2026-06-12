#!/bin/bash
set -euo pipefail

# ---------------- CONFIGURATION ----------------
FQDN="rocky-08-03.vgs.com"
IPADDRESS="192.168.253.143"
NETBOX_VERSION="v4.4.9"

DB_NAME="netbox"
DB_USER="netbox"
DB_PASS="Root@123"

ADMIN_USER="netadmin"
ADMIN_EMAIL="admin@example.com"
ADMIN_PASS="Netbox12345678"

NETBOX_ROOT="/opt/netbox"
PYTHON_BIN="/usr/bin/python3.12"

log() {
    echo -e "\e[32m[$(date '+%F %T')] $1\e[0m"
}

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root."
    exit 1
fi

# ---------------- PYTHON CHECK ----------------
if [[ ! -x "$PYTHON_BIN" ]]; then
    log "Python 3.12 not found. Installing..."

    dnf install -y epel-release

    dnf install -y \
        python3.12 \
        python3.12-devel \
        python3.12-pip

    if [[ ! -x "$PYTHON_BIN" ]]; then
        echo "ERROR: Failed to install Python 3.12"
        exit 1
    fi

    log "Python installed successfully"
fi

log "Using $($PYTHON_BIN --version)"

# ---------------- STOP OLD SERVICES ----------------
log "Stopping old services"

systemctl stop netbox 2>/dev/null || true
systemctl stop netbox-worker 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop redis 2>/dev/null || true
systemctl stop postgresql-15 2>/dev/null || true

pkill -9 gunicorn 2>/dev/null || true

# ---------------- REPOSITORIES ----------------
log "Configuring repositories"

dnf install -y epel-release dnf-plugins-core

dnf config-manager --set-enabled crb \
    || dnf config-manager --set-enabled powertools \
    || true

dnf remove -y pgdg-redhat-repo 2>/dev/null || true

dnf install -y python3.12

dnf install -y \
https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

dnf -qy module disable postgresql

# ---------------- REDIS 7 REPOSITORY ----------------
log "Enabling Redis 7 repository"

dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm

dnf module reset redis -y
dnf module enable redis:remi-7.2 -y

# ---------------- PACKAGES ----------------
log "Installing packages"

dnf install -y \
    python3.12 \
    python3.12-devel \
    python3.12-pip \
    git \
    gcc \
    make \
    redis \
    nginx \
    firewalld \
    openssl \
    openssl-devel \
    libffi-devel \
    libxml2-devel \
    libxslt-devel \
    libjpeg-turbo-devel \
    zlib-devel \
    postgresql15-server \
    postgresql15-devel

export PATH=$PATH:/usr/pgsql-15/bin

# ---------------- POSTGRESQL ----------------
log "Initializing PostgreSQL"

if [[ ! -d /var/lib/pgsql/15/data/base ]]; then
    /usr/pgsql-15/bin/postgresql-15-setup initdb
fi

systemctl enable --now postgresql-15
systemctl enable --now redis

log "Waiting for PostgreSQL"

until pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; do
    sleep 2
done

# ---------------- DATABASE ROLE ----------------
log "Creating PostgreSQL role"

su - postgres -c "psql" <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname='${DB_USER}'
    ) THEN
        CREATE ROLE ${DB_USER}
        LOGIN
        PASSWORD '${DB_PASS}';
    END IF;
END
\$\$;
EOF

# ---------------- DATABASE ----------------
log "Creating NetBox database"

if ! su - postgres -c \
"psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\"" \
| grep -q 1; then

    su - postgres -c \
    "createdb -O ${DB_USER} ${DB_NAME}"
fi

su - postgres -c "psql -d ${DB_NAME}" <<EOF
ALTER SCHEMA public OWNER TO ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

# ---------------- NETBOX ----------------
log "Downloading NetBox"

rm -rf "${NETBOX_ROOT}"

git clone \
    --branch "${NETBOX_VERSION}" \
    --depth 1 \
    https://github.com/netbox-community/netbox.git \
    "${NETBOX_ROOT}"

cd "${NETBOX_ROOT}"

# ---------------- PYTHON ----------------
log "Creating virtual environment"

rm -rf venv

"${PYTHON_BIN}" -m venv venv

source venv/bin/activate

pip install --upgrade pip setuptools wheel

pip install gunicorn "psycopg[c,pool]"

pip install -r requirements.txt

# ---------------- NETBOX CONFIGURATION ----------------
log "Configuring NetBox"

SECRET_KEY=$("${PYTHON_BIN}" netbox/generate_secret_key.py)
PEPPER=$("${PYTHON_BIN}" netbox/generate_secret_key.py)

cat > netbox/netbox/configuration.py <<EOF
import os

ALLOWED_HOSTS = [
    '${FQDN}',
    '${IPADDRESS}',
]

DEBUG = False

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DATABASE = {
    'NAME': '${DB_NAME}',
    'USER': '${DB_USER}',
    'PASSWORD': '${DB_PASS}',
    'HOST': '127.0.0.1',
    'PORT': '',
}

REDIS = {
    'tasks': {
        'HOST': '127.0.0.1',
        'PORT': 6379,
        'DATABASE': 0,
    },
    'caching': {
        'HOST': '127.0.0.1',
        'PORT': 6379,
        'DATABASE': 1,
    },
}

SECRET_KEY = '${SECRET_KEY}'

API_TOKEN_PEPPERS = {
    1: '${PEPPER}',
}

CSRF_TRUSTED_ORIGINS = [
    'https://${FQDN}',
    'http://${FQDN}',
]
EOF

# ---------------- REDIS CLEANUP ----------------
log "Cleaning Redis databases"

redis-cli -n 0 FLUSHDB || true
redis-cli -n 1 FLUSHDB || true

# ---------------- DATABASE MIGRATIONS ----------------
log "Running migrations"

export DJANGO_SETTINGS_MODULE=netbox.settings

python netbox/manage.py migrate

log "Collecting static files"

python netbox/manage.py collectstatic --noinput

# ---------------- ADMIN USER ----------------
log "Creating admin user"

python netbox/manage.py shell <<EOF
from django.contrib.auth import get_user_model

User = get_user_model()

if not User.objects.filter(username="${ADMIN_USER}").exists():
    User.objects.create_superuser(
        "${ADMIN_USER}",
        "${ADMIN_EMAIL}",
        "${ADMIN_PASS}"
    )
EOF

# ---------------- SYSTEMD ----------------
log "Creating systemd services"

cat > /etc/systemd/system/netbox.service <<EOF
[Unit]
Description=NetBox WSGI Service
After=network.target postgresql-15.service redis.service
Requires=postgresql-15.service redis.service

[Service]
Environment="DJANGO_SETTINGS_MODULE=netbox.settings"
WorkingDirectory=${NETBOX_ROOT}/netbox
ExecStart=${NETBOX_ROOT}/venv/bin/gunicorn \
    --bind 127.0.0.1:8001 \
    --workers 3 \
    --timeout 120 \
    netbox.wsgi

Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/netbox-worker.service <<EOF
[Unit]
Description=NetBox RQ Worker
After=network.target postgresql-15.service redis.service
Requires=postgresql-15.service redis.service

[Service]
Environment="DJANGO_SETTINGS_MODULE=netbox.settings"
WorkingDirectory=${NETBOX_ROOT}/netbox
ExecStart=${NETBOX_ROOT}/venv/bin/python manage.py rqworker
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ---------------- SSL ----------------
log "Generating self-signed certificate"

mkdir -p /etc/ssl/netbox

openssl req -x509 \
    -nodes \
    -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/ssl/netbox/netbox.key \
    -out /etc/ssl/netbox/netbox.crt \
    -subj "/C=US/ST=State/L=City/O=IT/CN=${FQDN}"

# ---------------- NGINX ----------------
log "Configuring Nginx"

cat > /etc/nginx/conf.d/netbox.conf <<EOF
server {
    listen 80;
    server_name ${FQDN};

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${FQDN};

    ssl_certificate /etc/ssl/netbox/netbox.crt;
    ssl_certificate_key /etc/ssl/netbox/netbox.key;

    location /static/ {
        alias ${NETBOX_ROOT}/netbox/static/;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

nginx -t

# ---------------- FIREWALL ----------------
log "Configuring firewall"

systemctl enable --now firewalld || true

firewall-cmd --permanent --add-service=http || true
firewall-cmd --permanent --add-service=https || true
firewall-cmd --reload || true

# ---------------- SELINUX ----------------
log "Setting SELinux to permissive (runtime)"

setenforce 0 2>/dev/null || true

# ---------------- START SERVICES ----------------
log "Starting services"

systemctl daemon-reexec
systemctl daemon-reload

systemctl enable --now netbox
systemctl enable --now netbox-worker
systemctl enable --now nginx

# ---------------- STATUS ----------------
log "Service status"

systemctl --no-pager --full status netbox || true
systemctl --no-pager --full status netbox-worker || true
systemctl --no-pager --full status nginx || true

# ---------------- COMPLETE ----------------
log "----------------------------------------"
log "NetBox installation completed"
log "URL : https://${FQDN}"
log "URL : https://${IPADDRESS}"
log "Username : ${ADMIN_USER}"
log "Password : ${ADMIN_PASS}"
log "----------------------------------------"
