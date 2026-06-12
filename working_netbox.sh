#!/bin/bash
set -euo pipefail

############################################################
# CONFIGURATION
############################################################
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

############################################################
# COLORS
############################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

############################################################
# DISPLAY FUNCTIONS
############################################################
print_line() {
    printf "%b\n" "${BLUE}=================================================================${NC}"
}

print_header() {
    echo
    print_line
    printf "%b\n" "${CYAN}$1${NC}"
    print_line
    echo
}

log_info() {
    printf "%b\n" "${GREEN}[$(date '+%F %T')] [INFO] $1${NC}"
}

log_warn() {
    printf "%b\n" "${YELLOW}[$(date '+%F %T')] [WARN] $1${NC}"
}

log_error() {
    printf "%b\n" "${RED}[$(date '+%F %T')] [ERROR] $1${NC}"
}

############################################################
# ROOT CHECK
############################################################
if [[ $EUID -ne 0 ]]; then
    log_error "Run this script as root."
    exit 1
fi

############################################################
# PYTHON CHECK
############################################################
print_header "CHECKING PYTHON 3.12"

if [[ ! -x "$PYTHON_BIN" ]]; then
    log_info "Python 3.12 not found. Installing..."

    dnf install -y epel-release

    dnf install -y \
        python3.12 \
        python3.12-devel \
        python3.12-pip

    if [[ ! -x "$PYTHON_BIN" ]]; then
        log_error "Failed to install Python 3.12"
        exit 1
    fi

    log_info "Python installed successfully"
fi

log_info "Using $($PYTHON_BIN --version)"

############################################################
# STOP OLD SERVICES
############################################################
print_header "STOPPING OLD SERVICES"

systemctl stop netbox 2>/dev/null || true
systemctl stop netbox-worker 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop redis 2>/dev/null || true
systemctl stop postgresql-15 2>/dev/null || true

pkill -9 gunicorn 2>/dev/null || true

############################################################
# REPOSITORIES
############################################################
print_header "CONFIGURING REPOSITORIES"

dnf install -y epel-release dnf-plugins-core

dnf config-manager --set-enabled crb \
    || dnf config-manager --set-enabled powertools \
    || true

dnf remove -y pgdg-redhat-repo 2>/dev/null || true

dnf install -y python3.12

dnf install -y \
https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

dnf -qy module disable postgresql

############################################################
# REDIS REPOSITORY
############################################################
print_header "ENABLING REDIS 7.2 REPOSITORY"

dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm

dnf module reset redis -y
dnf module enable redis:remi-7.2 -y

############################################################
# INSTALL PACKAGES
############################################################
print_header "INSTALLING REQUIRED PACKAGES"

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

############################################################
# POSTGRESQL
############################################################
print_header "INITIALIZING POSTGRESQL"

if [[ ! -d /var/lib/pgsql/15/data/base ]]; then
    /usr/pgsql-15/bin/postgresql-15-setup initdb
fi

systemctl enable --now postgresql-15
systemctl enable --now redis

log_info "Waiting for PostgreSQL..."

until pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; do
    sleep 2
done

log_info "PostgreSQL is ready"

############################################################
# POSTGRES ROLE
############################################################
print_header "CREATING POSTGRESQL ROLE"

su - postgres -c "psql" <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles
        WHERE rolname='${DB_USER}'
    ) THEN
        CREATE ROLE ${DB_USER}
        LOGIN
        PASSWORD '${DB_PASS}';
    END IF;
END
\$\$;
EOF

############################################################
# DATABASE
############################################################
print_header "CREATING NETBOX DATABASE"

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

############################################################
# DOWNLOAD NETBOX
############################################################
print_header "DOWNLOADING NETBOX"

rm -rf "${NETBOX_ROOT}"

git clone \
    --branch "${NETBOX_VERSION}" \
    --depth 1 \
    https://github.com/netbox-community/netbox.git \
    "${NETBOX_ROOT}"

cd "${NETBOX_ROOT}"

############################################################
# PYTHON VIRTUAL ENVIRONMENT
############################################################
print_header "CREATING PYTHON VIRTUAL ENVIRONMENT"

rm -rf venv

"${PYTHON_BIN}" -m venv venv

source venv/bin/activate

pip install --upgrade pip setuptools wheel

pip install gunicorn "psycopg[c,pool]"

pip install -r requirements.txt

log_info "Python dependencies installed"

############################################################
# NETBOX CONFIGURATION
############################################################
print_header "CONFIGURING NETBOX"

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

log_info "NetBox configuration created"

############################################################
# REDIS CLEANUP
############################################################
print_header "CLEANING REDIS DATABASES"

redis-cli -n 0 FLUSHDB || true
redis-cli -n 1 FLUSHDB || true

log_info "Redis cleanup completed"

############################################################
# DJANGO SETTINGS
############################################################
print_header "CONFIGURING DJANGO ENVIRONMENT"

export DJANGO_SETTINGS_MODULE=netbox.settings

############################################################
# DATABASE MIGRATIONS
############################################################
print_header "RUNNING DATABASE MIGRATIONS"

python netbox/manage.py migrate

log_info "Database migrations completed"

############################################################
# STATIC FILES
############################################################
print_header "COLLECTING STATIC FILES"

python netbox/manage.py collectstatic --noinput

log_info "Static files collected"

############################################################
# ADMIN USER
############################################################
print_header "CREATING ADMIN USER"

python netbox/manage.py shell <<EOF
from django.contrib.auth import get_user_model

User = get_user_model()

if not User.objects.filter(username="${ADMIN_USER}").exists():
    User.objects.create_superuser(
        "${ADMIN_USER}",
        "${ADMIN_EMAIL}",
        "${ADMIN_PASS}"
    )
    print("Superuser created")
else:
    print("Superuser already exists")
EOF

log_info "Admin account verified"

############################################################
# NETBOX HEALTH CHECK
############################################################
print_header "VERIFYING NETBOX INSTALLATION"

python netbox/manage.py check

log_info "Django checks completed successfully"

############################################################
# PREPARE FOR SERVICES
############################################################
print_header "PREPARING SYSTEM SERVICES"

mkdir -p /var/log/netbox

chown -R root:root "${NETBOX_ROOT}"

log_info "System preparation completed"

############################################################
# SYSTEMD SERVICES
############################################################
print_header "CREATING SYSTEMD SERVICES"

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
RestartSec=5

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
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

log_info "Systemd service files created"

############################################################
# SSL CERTIFICATE
############################################################
print_header "GENERATING SELF-SIGNED SSL CERTIFICATE"

mkdir -p /etc/ssl/netbox

openssl req -x509 \
    -nodes \
    -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/ssl/netbox/netbox.key \
    -out /etc/ssl/netbox/netbox.crt \
    -subj "/C=US/ST=State/L=City/O=IT/CN=${FQDN}"

chmod 600 /etc/ssl/netbox/netbox.key

log_info "SSL certificate generated"

############################################################
# NGINX CONFIGURATION
############################################################
print_header "CONFIGURING NGINX"

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

    client_max_body_size 25m;

    location /static/ {
        alias ${NETBOX_ROOT}/netbox/static/;
        expires 30d;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        proxy_redirect off;
    }
}
EOF

nginx -t

log_info "Nginx configuration validated"

############################################################
# FIREWALL
############################################################
print_header "CONFIGURING FIREWALL"

systemctl enable --now firewalld || true

firewall-cmd --permanent --add-service=http || true
firewall-cmd --permanent --add-service=https || true

firewall-cmd --reload || true

log_info "Firewall configuration completed"

############################################################
# SELINUX
############################################################
print_header "CONFIGURING SELINUX"

setenforce 0 2>/dev/null || true

log_info "SELinux set to permissive mode (runtime)"

############################################################
# START SERVICES
############################################################
print_header "STARTING SERVICES"

systemctl daemon-reexec
systemctl daemon-reload

systemctl enable netbox
systemctl enable netbox-worker
systemctl enable nginx

systemctl restart netbox
systemctl restart netbox-worker
systemctl restart nginx

log_info "Services started"

############################################################
# VERIFY SERVICES
############################################################
print_header "VERIFYING SERVICE STATUS"

sleep 5

systemctl --no-pager --full status netbox || true
systemctl --no-pager --full status netbox-worker || true
systemctl --no-pager --full status nginx || true

############################################################
# NETBOX URL TEST
############################################################
print_header "TESTING NETBOX"

curl -k -I https://127.0.0.1 2>/dev/null || true

############################################################
# INSTALLATION COMPLETE
############################################################
print_header "NETBOX INSTALLATION COMPLETED"

printf "%b\n" "${GREEN}URL      : https://${FQDN}${NC}"
printf "%b\n" "${GREEN}URL      : https://${IPADDRESS}${NC}"
printf "%b\n" "${GREEN}Username : ${ADMIN_USER}${NC}"
printf "%b\n" "${GREEN}Password : ${ADMIN_PASS}${NC}"

echo
print_line

printf "%b\n" "${GREEN}"
echo "############################################################"
echo "#                                                          #"
echo "#           NETBOX INSTALLATION SUCCESSFUL                 #"
echo "#                                                          #"
echo "############################################################"
printf "%b\n" "${NC}"

echo
log_info "NetBox deployment completed successfully."
