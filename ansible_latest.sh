#!/bin/bash

set -e

echo "🔧 Installing system dependencies..."
dnf install epel-release -y
dnf install git gcc gcc-c++ nodejs gettext device-mapper-persistent-data lvm2 bzip2 -y

echo "🧹 Removing old Python 3.6..."
dnf remove python36 -y

echo "🐍 Switching to Python 3.9..."
dnf module reset python36 -y
dnf module enable python39 -y
dnf install python39 python39-pip -y

echo "📦 Upgrading pip and installing Docker libraries for Python 3.9..."
python3.9 -m pip install --upgrade pip
python3.9 -m pip install docker docker-compose requests==2.31.0

echo "🐳 Setting up Docker CE repository..."
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

echo "🧹 Cleaning up old runc..."
dnf remove runc* -y || true

echo "🐳 Installing Docker CE and runc..."
dnf install docker-ce* runc* -y

echo "🚀 Starting Docker service..."
systemctl enable --now docker

echo "📦 Installing Docker Compose v1 (for compatibility)..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

echo "📁 Cloning AWX installer..."
if [ ! -d "awx" ]; then
    git clone -b "17.1.0" https://github.com/ansible/awx.git
fi
cd awx/installer

sed -i 's|ansible_python_interpreter="/usr/bin/env python3"|ansible_python_interpreter="/usr/bin/env python3.9"|' /root/awx/installer/inventory

echo "📝 Updating inventory file..."
# Ensure pg_password
if grep -q '^pg_password=' inventory; then
  sed -i 's/^pg_password=.*/pg_password=redhat123/' inventory
elif grep -q '^#pg_password=' inventory; then
  sed -i 's/^#pg_password=.*/pg_password=redhat123/' inventory
else
  echo "pg_password=redhat123" >> inventory
fi

# Ensure pg_admin_password
if grep -q '^pg_admin_password=' inventory; then
  sed -i 's/^pg_admin_password=.*/pg_admin_password=redhat123/' inventory
elif grep -q '^#pg_admin_password=' inventory; then
  sed -i 's/^#pg_admin_password=.*/pg_admin_password=redhat123/' inventory
else
  echo "pg_admin_password=redhat123" >> inventory
fi

# Ensure admin_password
if grep -q '^admin_password=' inventory; then
  sed -i 's/^admin_password=.*/admin_password=redhat123/' inventory
elif grep -q '^#admin_password=' inventory; then
  sed -i 's/^#admin_password=.*/admin_password=redhat123/' inventory
else
  echo "admin_password=redhat123" >> inventory
fi

# Ensure project_data_dir
if grep -q '^project_data_dir=' inventory; then
  sed -i 's|^project_data_dir=.*|project_data_dir=/var/lib/awx/projects|' inventory
elif grep -q '^#project_data_dir=' inventory; then
  sed -i 's|^#project_data_dir=.*|project_data_dir=/var/lib/awx/projects|' inventory
else
  echo "project_data_dir=/var/lib/awx/projects" >> inventory
fi

echo "📂 Ensuring project data directory exists..."
mkdir -p /var/lib/awx/projects
chown 1000:1000 /var/lib/awx/projects

echo "🛠️ Replacing deprecated docker_service with docker_compose_v2..."
sed -i 's/docker_service:/community.docker.docker_compose_v2:/g' roles/local_docker/tasks/upgrade_postgres.yml
sed -i 's/docker_service:/community.docker.docker_compose_v2:/g' roles/local_docker/tasks/compose.yml

echo "🧠 Fixing Python Docker client environment bug for Python 3.9..."
cp /usr/local/lib/python3.9/site-packages/compose/cli/docker_client.py \
   /usr/local/lib/python3.9/site-packages/compose/cli/docker_client.py-bkp || true
sed -i 's/kwargs = kwargs_from_env(environment=environment, ssl_version=tls_version)/kwargs = kwargs_from_env(environment=environment)/' \
   /usr/local/lib/python3.9/site-packages/compose/cli/docker_client.py || true

echo "🔄 Updating AWX task logic..."
# Fix upgrade_postgres.yml: replace 'stopped: true' with 'state: absent'
sed -i '/name: Stop AWX before upgrading postgres/{n;s/stopped: true/state: absent/}' roles/local_docker/tasks/upgrade_postgres.yml

# Fix compose.yml: replace 'restarted' with 'recreate' and add 'state: present'
sed -i '/name: Start the containers/{n;s/restarted:.*/recreate: "{{ (awx_compose_config is changed or awx_secret_key is changed) | ternary('\''always'\'', '\''never'\'') }}"\n        state: present/}' roles/local_docker/tasks/compose.yml

echo "🔐 Generating self-signed SSL certificates..."
openssl genrsa -out pvt.pem 2048
openssl req -new -key pvt.pem -out cert.pem \
  -subj "/C=IN/ST=Tamilnadu/L=Chennai/O=AWX/OU=AWX/CN=test-pxe01.vgs.com"
openssl x509 -req -days 3650 -in cert.pem -signkey pvt.pem -out cert.pem

echo "📂 Preparing AWX SSL directory..."
mkdir -p /etc/ssl/awx
cp cert.pem /etc/ssl/awx/awx.crt
cp pvt.pem /etc/ssl/awx/awx.key
chmod 600 /etc/ssl/awx/awx.key

echo "📝 Updating inventory with SSL configuration..."
if ! grep -q '^ssl_certificate=' inventory; then
  echo "ssl_certificate=/etc/ssl/awx/awx.crt" >> inventory
fi
if ! grep -q '^ssl_certificate_key=' inventory; then
  echo "ssl_certificate_key=/etc/ssl/awx/awx.key" >> inventory
fi
if ! grep -q '^ssl_redirect=' inventory; then
  echo "ssl_redirect=true" >> inventory
fi

echo "🚀 Running AWX installer playbook with SSL..."
ansible-playbook -i inventory install.yml

firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload

echo "🔄 Running database migrations and restarting AWX services..."
docker exec -it awx_task awx-manage migrate
docker restart awx_web awx_task

echo "✅ AWX installation complete. Access it via https://localhost or your server IP."
