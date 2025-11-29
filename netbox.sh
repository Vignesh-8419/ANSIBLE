#!/bin/bash
set -e

echo "=== 🚀 Starting NetBox Automated Installation on Rocky Linux 8 ==="

# 1️⃣ Install dependencies
echo "[1/14] Installing dependencies..."
dnf install -y epel-release
dnf module disable -y postgresql
dnf module enable -y postgresql:15
dnf install -y python3.11 python3.11-devel gcc nginx redis git postgresql postgresql-server postgresql-contrib

# 2️⃣ Initialize PostgreSQL
echo "[2/14] Initializing PostgreSQL..."
if [ ! -f /var/lib/pgsql/data/PG_VERSION ]; then
    /usr/bin/postgresql-setup --initdb
fi
systemctl enable --now postgresql

# 3️⃣ Configure PostgreSQL authentication
echo "[3/14] Configuring PostgreSQL authentication..."
PG_HBA="/var/lib/pgsql/data/pg_hba.conf"
cat <<EOF > "$PG_HBA"
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF

chown postgres:postgres "$PG_HBA"
chmod 600 "$PG_HBA"
systemctl restart postgresql

# 4️⃣ Configure PostgreSQL users and DB
echo "[4/14] Setting PostgreSQL user and database..."
cd /tmp
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'Root@123';"

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='netbox'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE USER netbox WITH PASSWORD 'Root@123';"
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='netbox'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE DATABASE netbox OWNER netbox;"
fi

# 5️⃣ Clone NetBox
echo "[5/14] Cloning NetBox source..."
cd /opt
if [ ! -d "/opt/netbox" ]; then
    git clone -b v3.7.1 https://github.com/netbox-community/netbox.git
fi
cd /opt/netbox

# 6️⃣ Python virtual environment
echo "[6/14] Creating Python venv..."
/usr/bin/python3.11 -m venv /opt/netbox/venv
source /opt/netbox/venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn
deactivate

# 7️⃣ NetBox configuration
echo "[7/14] Configuring NetBox..."
cp netbox/netbox/configuration_example.py netbox/netbox/configuration.py
SECRET_KEY=$(openssl rand -hex 32)
cat <<EOF > netbox/netbox/configuration.py
#ALLOWED_HOSTS = ['*']
ALLOWED_HOSTS = ['192.168.253.134', 'localhost']

DATABASE = {
    'NAME': 'netbox',
    'USER': 'netbox',
    'PASSWORD': 'Root@123',
    'HOST': 'localhost',
    'PORT': '',
}

SECRET_KEY = '${SECRET_KEY}'

REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'DATABASE': 1,
        'SSL': False,
    }
}
EOF

# 8️⃣ Enable Redis
echo "[8/14] Enabling Redis..."
systemctl enable --now redis

echo "⏳ Waiting for Redis to become available..."
until redis-cli ping | grep -q PONG; do
    sleep 1
done

# 9️⃣ Run migrations & create superuser
echo "[9/14] Running DB migrations..."
cd /opt/netbox/netbox
source /opt/netbox/venv/bin/activate
python manage.py migrate

echo "
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', 'admin@example.com', 'adminpass')
" | python manage.py shell

python manage.py collectstatic --no-input
deactivate

# 🔟 Nginx configuration
echo "[10/14] Configuring Nginx..."
cat <<'EOF' > /etc/nginx/conf.d/netbox.conf
server {
    listen 80 ;
    server_name _;

    location /static/ {
        alias /opt/netbox/netbox/static/;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 🔧 config nginx.conf
>/etc/nginx/nginx.conf
cat <<'EOF' > "/etc/nginx/nginx.conf"
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

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

    # HTTPS server for NetBox
    server {
        listen 443 ssl http2;
        server_name _;

        ssl_certificate     /etc/nginx/ssl/netbox.crt;
        ssl_certificate_key /etc/nginx/ssl/netbox.key;
        ssl_session_cache   shared:SSL:1m;
        ssl_session_timeout 10m;
        ssl_ciphers PROFILE=SYSTEM;
        ssl_prefer_server_ciphers on;

        location /static/ {
            alias /opt/netbox/netbox/static/;
        }

        location / {
            proxy_pass http://127.0.0.1:8001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        error_page 404 /404.html;
        location = /40x.html { }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html { }
    }

    # Redirect HTTP → HTTPS
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }
}

EOF


# 🔧 Remove default welcome page config
echo "[10.2/14] Removing default Nginx site..."
rm -f /etc/nginx/conf.d/default.conf || true

# 11️⃣ Disable SELinux temporarily
echo "[11/14] Disabling SELinux enforcement..."
setenforce 0 || true

# 12️⃣ Create systemd service for NetBox
echo "[12/14] Creating NetBox systemd service..."
cat <<'EOF' > /etc/systemd/system/netbox.service
[Unit]
Description=NetBox WSGI Service
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/netbox/netbox
Environment="PATH=/opt/netbox/venv/bin"
ExecStart=/opt/netbox/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8001 netbox.wsgi
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now netbox

# 13️⃣ Firewall open (optional)
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "[13/14] Configuring firewall..."
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --reload || true
fi

# 14️⃣ Final Nginx restart
echo "[14/14] Restarting Nginx to apply all changes..."
nginx -t && systemctl restart nginx

sed -i -E 's/listen[[:space:]]+80[[:space:]]+default_server;/listen 80;/; s/listen[[:space:]]+ \[::\] :80[[:space:]]+default_server;/listen [::]:80;/' /etc/nginx/nginx.conf
systemctl start nginx
nginx -t && systemctl reload nginx

# ✅ Done
echo "=== ✅ NetBox installation completed successfully! ==="
echo "Access NetBox via: http://<your_server_ip>/"
echo "If this is a fresh install, login with: username=admin, password=adminpass"
