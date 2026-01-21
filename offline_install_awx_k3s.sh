#!/bin/bash
set -e

# ---------------- CONFIGURATION ----------------
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
ADMIN_PASSWORD="Root@123"
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# ---------------- FUNCTIONS ----------------
log() { echo -e "\e[32m✔ $1\e[0m"; }
error_exit() { echo -e "\e[31m✘ $1\e[0m"; exit 1; }

# ---------------- 1. REPOSITORY SETUP ----------------
log "Configuring all local repositories..."
rm -rf /etc/yum.repos.d/*

cat <<EOF > /etc/yum.repos.d/internal_mirror.repo
[local-extras]
name=Local Rocky Extras
baseurl=https://${REPO_SERVER}/repo/ansible_offline_repo/extras
enabled=1
gpgcheck=0
sslverify=0

[local-rancher]
name=Local Rancher K3s
baseurl=https://${REPO_SERVER}/repo/ansible_offline_repo/rancher-k3s-common-stable
enabled=1
gpgcheck=0
sslverify=0

[local-packages]
name=Local Core Dependencies
baseurl=https://${REPO_SERVER}/repo/ansible_offline_repo/packages
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

[rocky8-baseos]
name=Rocky Linux 8 BaseOS
baseurl=https://${REPO_SERVER}/repo/rocky8/BaseOS
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true

[rocky8-appstream]
name=Rocky Linux 8 AppStream
baseurl=https://${REPO_SERVER}/repo/rocky8/Appstream
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true

[rocky8-rhel-installed]
name=Rocky Linux 8 Installed RHEL
baseurl=https://${REPO_SERVER}/repo/installed_rhel8
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

log "Refreshing DNF cache..."
dnf clean all
dnf makecache

log "Installing prerequisites..."
dnf install -y curl net-tools tar openssl git make

# ---------------- 2. OFFLINE BINARIES ----------------
log "Downloading offline binaries (K3s, Kustomize)..."
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/k3s -o /usr/local/bin/k3s
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/kustomize -o /usr/local/bin/kustomize
chmod +x /usr/local/bin/k3s /usr/local/bin/kustomize
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ---------------- 3. K3S INSTALLATION ----------------
log "Starting K3s..."
# Check for VIP
if ! ip addr show $INTERFACE | grep -q "$VIP"; then
    ip addr add $VIP/24 dev $INTERFACE || log "VIP already exists or failed to add"
fi

export INSTALL_K3S_SKIP_DOWNLOAD=true
# Start K3s in background
k3s server --write-kubeconfig-mode 644 --bind-address $VIP --advertise-address $VIP &

log "Waiting for K3s API to respond..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes &>/dev/null; do
    sleep 5
    echo -n "."
done
echo ""

# ---------------- 4. LOADING IMAGES ----------------
log "Importing AWX and K3s Container Images (This may take several minutes)..."
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/images/awx-images.tar -o /tmp/images.tar
k3s ctr images import /tmp/images.tar

# ---------------- 5. AWX OPERATOR ----------------
log "Setting up AWX Operator source..."
curl -kL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/awx-operator-${OPERATOR_VERSION}.tar.gz -o /tmp/awx-op.tgz
mkdir -p /opt/awx-operator
tar -xzf /tmp/awx-op.tgz -C /opt/awx-operator --strip-components=1

log "Creating AWX Namespace and Secret..."
kubectl create namespace $NAMESPACE || true
kubectl create secret generic awx-server-admin-password --from-literal=password=$ADMIN_PASSWORD -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

log "Deploying AWX Operator via Make..."
cd /opt/awx-operator
make deploy NAMESPACE=$NAMESPACE

log "Waiting for Operator pod to be Ready..."
until [ "$(kubectl get pods -n $NAMESPACE -l control-plane=controller-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" == "Running" ]; do
    sleep 10
    echo -n "."
done
echo ""

# ---------------- 6. AWX INSTANCE ----------------
log "Creating AWX Instance..."
cat <<EOF > /opt/awx-operator/awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
spec:
  service_type: ClusterIP
  admin_password_secret: awx-server-admin-password
  postgres_storage_class: local-path
EOF

kubectl apply -f /opt/awx-operator/awx-instance.yaml -n $NAMESPACE

log "-------------------------------------------------------"
log "SUCCESS: AWX Installation has been initiated."
log "Monitor progress: kubectl get pods -n $NAMESPACE -w"
log "Access URL: http://$VIP (after pods are ready)"
log "-------------------------------------------------------"
