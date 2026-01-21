#!/bin/bash
set -e

# ---------------- CONFIGURATION ----------------
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
ADMIN_PASSWORD="Root@123"
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# ---------------- REPOSITORY SETUP ----------------
log "Configuring all local repositories..."

# Clear existing repos to prevent external lookups
rm -rf /etc/yum.repos.d/*

# 1. Internal Application Mirrors
cat <<EOF > /etc/yum.repos.d/internal_mirror.repo
[local-extras]
name=Local Rocky Extras
baseurl=https://192.168.253.136/repo/offline_repo/extras
enabled=1
gpgcheck=0
sslverify=0

[local-rancher]
name=Local Rancher K3s
baseurl=https://192.168.253.136/repo/offline_repo/rancher-k3s-common-stable
enabled=1
gpgcheck=0
sslverify=0

[local-packages]
name=Local Core Dependencies
baseurl=https://192.168.253.136/repo/offline_repo/packages
enabled=1
gpgcheck=0
sslverify=0

[netbox-offline]
name=NetBox Offline Repository
baseurl=https://192.168.253.136/repo/netbox_offline_repo/rpms
enabled=1
gpgcheck=0
sslverify=0
priority=1
EOF

# 2. Rocky Linux OS Repositories
cat <<EOF > /etc/yum.repos.d/rocky8-baseos.repo
[rocky8-baseos]
name=Rocky Linux 8 BaseOS
baseurl=https://192.168.253.136/repo/rocky8/BaseOS
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

cat <<EOF > /etc/yum.repos.d/rocky8-appstream.repo
[rocky8-appstream]
name=Rocky Linux 8 AppStream
baseurl=https://192.168.253.136/repo/rocky8/Appstream
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

# 3. Installed RHEL Compatibility Repo
cat <<EOF > /etc/yum.repos.d/rocky8-rhel-installed.repo
[rocky8-rhel-installed]
name=Rocky Linux 8 Installed RHEL
baseurl=https://192.168.253.136/repo/installed_rhel8
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

# Refresh the cache
dnf clean all
dnf makecache

log "Installing prerequisites..."
dnf install -y curl net-tools tar openssl

# ---------------- 2. OFFLINE BINARIES ----------------
log "Downloading offline binaries (K3s, Kustomize)..."
# Download from your /binaries folder
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/k3s -o /usr/local/bin/k3s
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/kustomize -o /usr/local/bin/kustomize
chmod +x /usr/local/bin/k3s /usr/local/bin/kustomize
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ---------------- 3. K3S INSTALLATION ----------------
log "Installing K3s in offline mode..."
# Use --skip-deploy traefik if you prefer Nginx, but we'll stay with default for now
# --airgap-extra-append ensures it doesn't try to phone home
INSTALL_K3S_SKIP_DOWNLOAD=true k3s server \
    --write-kubeconfig-mode 644 \
    --bind-address $VIP \
    --advertise-address $VIP &

# Wait for K3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes &>/dev/null; do sleep 2; done

# ---------------- 4. LOADING IMAGES ----------------
log "Importing AWX and K3s Container Images..."
# This assumes you have bundled images into a tarball
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/images/awx-images.tar -o /tmp/images.tar
k3s ctr images import /tmp/images.tar

# ---------------- 5. AWX OPERATOR (OFFLINE SOURCE) ----------------
log "Extracting AWX Operator source..."
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/awx-operator-${OPERATOR_VERSION}.tar.gz -o /tmp/awx-op.tgz
mkdir -p /opt/awx-operator
tar -xzf /tmp/awx-op.tgz -C /opt/awx-operator --strip-components=1
cd /opt/awx-operator

log "Deploying AWX Operator..."
kubectl create namespace $NAMESPACE || true
kubectl create secret generic awx-server-admin-password --from-literal=password=$ADMIN_PASSWORD -n $NAMESPACE || true

# Deploy using local kustomize
kustomize build config/default | kubectl apply -f -

# ---------------- 6. AWX INSTANCE ----------------
log "Creating AWX Instance..."
cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
spec:
  service_type: ClusterIP
  admin_password_secret: awx-server-admin-password
  postgres_storage_class: local-path
EOF
kubectl apply -f awx-instance.yaml -n $NAMESPACE

log "AWX Offline Setup Initiated. Check status with: kubectl get pods -n $NAMESPACE"
