#!/bin/bash

set -e

echo "🔧 Installing system dependencies..."
dnf install epel-release -y
dnf install git gcc gcc-c++ ansible nodejs gettext device-mapper-persistent-data lvm2 bzip2 python3-pip -y

echo "🐳 Setting up Docker CE repository..."
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

echo "🧹 Cleaning up old runc..."
dnf remove runc* -y

echo "🐳 Installing Docker CE and runc..."
dnf install docker-ce* runc* -y

echo "🚀 Starting Docker service..."
systemctl enable --now docker

echo "📦 Installing Docker Compose v1 (for compatibility)..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

echo "🐍 Installing Python Docker libraries..."
pip3 install docker
pip3 install --upgrade pip
pip3 install --upgrade docker-compose

echo "📁 Cloning AWX installer..."
git clone -b "13.0.0" https://github.com/ansible/awx.git
cd awx/installer

echo "📝 Updating inventory file..."
sed -i 's/^pg_password=.*/pg_password=redhat123/' inventory
sed -i 's/^pg_admin_password=.*/pg_admin_password=redhat123/' inventory
sed -i 's/^admin_password=.*/admin_password=redhat123/' inventory
sed -i 's/^#project_data_dir=.*/project_data_dir=\/var\/lib\/awx\/projects/' inventory

echo "📂 Ensuring project data directory exists..."
mkdir -p /var/lib/awx/projects
chown 1000:1000 /var/lib/awx/projects

echo "🛠️ Replacing deprecated docker_service with docker_compose_v2..."
sed -i 's/docker_service:/community.docker.docker_compose_v2:/g' roles/local_docker/tasks/upgrade_postgres.yml
sed -i 's/docker_service:/community.docker.docker_compose_v2:/g' roles/local_docker/tasks/compose.yml

echo "🧠 Fixing Python Docker client environment bug..."
cp /usr/local/lib/python3.6/site-packages/compose/cli/docker_client.py /usr/local/lib/python3.6/site-packages/compose/cli/docker_client.py-bkp
sed -i 's/kwargs = kwargs_from_env(environment=environment, ssl_version=tls_version)/kwargs = kwargs_from_env(environment=environment)/' /usr/local/lib/python3.6/site-packages/compose/cli/docker_client.py

echo "🔄 Updating AWX task logic..."

# Fix upgrade_postgres.yml: replace 'stopped: true' with 'state: absent'
sed -i '/name: Stop AWX before upgrading postgres/{n;s/stopped: true/state: absent/}' roles/local_docker/tasks/upgrade_postgres.yml

# Fix compose.yml: replace 'restarted' with 'recreate' and add 'state: present'
sed -i '/name: Start the containers/{n;s/restarted:.*/recreate: "{{ (awx_compose_config is changed or awx_secret_key is changed) | ternary('\''always'\'', '\''never'\'') }}"\n        state: present/}' roles/local_docker/tasks/compose.yml

echo "🚀 Running AWX installer playbook..."
ansible-playbook -i inventory install.yml

/usr/libexec/platform-python -m pip uninstall -y pyvmomi pyVim
/usr/libexec/platform-python -m pip install pyvmomi==7.0.3 pyvim
/usr/libexec/platform-python -c "import pyVmomi, pyVim; print('OK')"

firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload

docker exec -it awx_task awx-manage migrate
docker restart awx_web awx_task

pip install ansible-tower-cli --user
# or for newer versions:
pip install awxkit --user

docker exec -it awx_task bash
ansible-galaxy collection install theforeman.foreman -p /usr/share/ansible/collections

echo "✅ AWX installation complete. Access it via http://localhost or your server IP."
