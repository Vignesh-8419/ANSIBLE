#!/bin/bash
set -e

# --- Configuration ---
FQDN="rocky-08-02.vgs.com"
DB_NAME="netbox"
DB_USER="netbox"
DB_PASS="Root@123"
NETBOX_ROOT="/opt/netbox"

log() { echo -e "\e[32m🚀 $1\e[0m"; }

log "1. Cleaning up existing services and ports..."
systemctl stop netbox netbox-worker nginx redis postgresql-15 postgresql || true
# Kill any lingering gunicorn processes
pkill -9 gunicorn || true

log "2. Ensuring PowerTools and EPEL are active..."
dnf install -y dnf-plugins-core epel-release
dnf config-manager --set-enabled powertools || dnf config-manager --set-enabled crb

log "3. Refreshing PostgreSQL 15 Repositories..."
dnf remove -y pgdg-redhat-repo || true
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql

log "4. Installing System Dependencies..."
dnf install -y python3.12 python3.12-devel python3.12-pip \
    git gcc openssl-devel libffi-devel libxml2-devel \
    libxslt-devel libjpeg-turbo-devel zlib-devel redis nginx openssl \
    postgresql15-server postgresql15-devel -y

# Explicitly set PATH for pg_config
export PATH=$PATH:/usr/pgsql-15/bin

log "5. Resetting Database..."
if [ ! -d "/var/lib/pgsql/15/data/base" ]; then
    /usr/pgsql-15/bin/postgresql-15-setup initdb
fi
systemctl enable --now postgresql-15 redis

# Force recreate the DB to ensure no v3/v4 schema mix
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"
sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;"
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
sudo -u postgres psql -d $DB_NAME -c "ALTER SCHEMA public OWNER TO $DB_USER;"

log "6. Fresh Clone of NetBox (Main Branch)..."
rm -rf $NETBOX_ROOT
git clone -b main --depth 1 https://github.com/netbox-community/netbox.git $NETBOX_ROOT

log "7. Building Virtual Environment with Python 3.12..."
cd $NETBOX_ROOT
# Remove any old venv just in case
rm -rf venv
/usr/bin/python3.12 -m venv venv
source venv/bin/activate

# Use the venv's pip explicitly
pip install --upgrade pip
pip install wheel gunicorn  # Install gunicorn inside the venv
pip install "psycopg[c,pool]"
pip install -r requirements.txt

log "8. Configuring NetBox..."
SECRET_KEY=$(python3 netbox/generate_secret_key.py)
PEPPER=$(python3 netbox/generate_secret_key.py)

cat <<EOF > $NETBOX_ROOT/netbox/netbox/configuration.py
ALLOWED_HOSTS = ['*']
DATABASE = {
    'NAME': '$DB_NAME',
    'USER': '$DB_USER',
    'PASSWORD': '$DB_PASS',
    'HOST': 'localhost',
    'PORT': '',
}
REDIS = {
    'tasks': {'HOST': 'localhost', 'PORT': 6379, 'DATABASE': 0},
    'caching': {'HOST': 'localhost', 'PORT': 6379, 'DATABASE': 1},
}
SECRET_KEY = '$SECRET_KEY'
API_TOKEN_PEPPERS = {1: '$PEPPER'}
CSRF_TRUSTED_ORIGINS = ['https://$FQDN', 'http://$FQDN']
EOF

log "9. Running Migrations & Static Files..."
# Clear Redis cache before migrating
redis-cli flushall
python3 netbox/manage.py migrate
python3 netbox/manage.py collectstatic --noinput

log "10. Creating Superuser..."
echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.create_superuser('netadmin', 'admin@example.com', 'Netbox12345678')" | python3 netbox/manage.py shell

log "11. Updating Systemd Units..."
# Note the explicit path to the venv gunicorn
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
Description=NetBox Background Worker
After=network.target

[Service]
WorkingDirectory=$NETBOX_ROOT/netbox
ExecStart=$NETBOX_ROOT/venv/bin/python3 netbox/manage.py runworker
Restart=always

[Install]
WantedBy=multi-user.target
EOF

log "12. Finalizing SSL and Nginx..."
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
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

systemctl daemon-reload
systemctl enable --now netbox netbox-worker nginx
firewall-cmd --permanent --add-service={http,https}
firewall-cmd --reload || true

log "-------------------------------------------------------"
log "✅ CLEAN INSTALL COMPLETE"
log "URL: https://$FQDN"
log "User: netadmin / Pass: Netbox12345678"
log "-------------------------------------------------------"
