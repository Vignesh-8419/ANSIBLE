#!/bin/bash

# --- CONFIGURATION ---
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
INTERFACE="ens192"
AWX_VERSION="24.6.1"
OPERATOR_VERSION="2.19.1"

set -e

log() { echo -e "\e[32m✔ $1\e[0m"; }
error_exit() { echo -e "\e[31m✘ $1\e[0m"; exit 1; }

# ---------------- 1. REPOS & DEPENDENCIES ----------------
log "Configuring local YUM repositories..."
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
EOF

cat <<EOF > /etc/yum.repos.d/rocky8-baseos.repo
[rocky8-baseos]
name=Rocky Linux 8 BaseOS
baseurl=https://${REPO_SERVER}/repo/rocky8/BaseOS
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

cat <<EOF > /etc/yum.repos.d/rocky8-appstream.repo
[rocky8-appstream]
name=Rocky Linux 8 AppStream
baseurl=https://${REPO_SERVER}/repo/rocky8/Appstream
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

yum clean all
yum install -y psmisc socat conntrack-tools ipset-service || true

# ---------------- 2. NUCLEAR CLEANUP ----------------
log "Performing nuclear cleanup..."
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
pkill -9 -x k3s || true
pkill -9 -x containerd || true
cat /proc/mounts | grep -E 'k3s|kubelet' | awk '{print $2}' | sort -r | xargs -r umount -l || true
fuser -k 6443/tcp 2>/dev/null || true
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s /var/log/k3s_install.log

# ---------------- 3. NETWORK & BINARIES ----------------
if ! ip addr show $INTERFACE | grep -q $VIP; then
    ip addr add ${VIP}/24 dev $INTERFACE || true
fi

log "Downloading K3s..."
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/k3s -o /usr/local/bin/k3s
chmod +x /usr/local/bin/k3s
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ---------------- 4. START K3S ----------------
log "Starting K3s..."
nohup /usr/local/bin/k3s server \
    --write-kubeconfig-mode 644 \
    --bind-address $VIP \
    --advertise-address $VIP \
    --node-ip $VIP \
    --disable traefik \
    --data-dir /var/lib/rancher/k3s \
    >> /var/log/k3s_install.log 2>&1 &

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes &>/dev/null; do sleep 3; echo -n "."; done
log " Connected!"

# ---------------- 5. IMPORT IMAGES ----------------
log "Importing Images..."
IMAGE_FILES=("k3s-airgap-images.tar" "awx.tar" "awx-operator.tar" "postgres.tar" "redis.tar")
for IMG in "${IMAGE_FILES[@]}"; do
    curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/images/$IMG -o /tmp/$IMG
    /usr/local/bin/k3s ctr images import /tmp/$IMG && rm -f /tmp/$IMG
done

# ---------------- 6. DEPLOY OPERATOR (FULL MANIFEST) ----------------
log "Applying Full AWX Operator Manifest..."
kubectl create namespace awx || true

# We download the full manifest once from your repo if available, 
# but if it's missing, we MUST use a local file.
# PLEASE ENSURE YOU RUN THIS ON YOUR REPO SERVER TO PROVIDE THE FILE:
# curl -L https://raw.githubusercontent.com/ansible/awx-operator/2.19.1/deploy/awx-operator.yaml > /var/www/html/repo/ansible_offline_repo/manifests/awx-operator.yaml

curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/manifests/awx-operator.yaml -o /tmp/awx-operator.yaml

if [ ! -s /tmp/awx-operator.yaml ]; then
    error_exit "CRITICAL: /tmp/awx-operator.yaml is empty. You MUST upload the official 2.19.1 manifest to your repo server."
fi

kubectl apply -f /tmp/awx-operator.yaml

log "Waiting for CRDs to register..."
sleep 20

# ---------------- 7. DEPLOY AWX INSTANCE ----------------
log "Creating AWX Instance..."
kubectl create secret generic awx-server-admin-password \
    --from-literal=password='Root@123' -n awx --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF > /tmp/awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  service_type: loadbalancer
  admin_user: admin
  admin_password_secret: awx-server-admin-password
  postgres_extra_container_params:
    - name: postgres
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        fsGroup: 0
EOF

# Loop until the CRD is actually recognized by the cluster
MAX_RETRIES=20
while ! kubectl apply -f /tmp/awx-instance.yaml -n awx 2>/dev/null; do
    echo "Waiting for Operator to initialize CRDs..."
    sleep 10
    ((MAX_RETRIES--))
    if [ $MAX_RETRIES -le 0 ]; then error_exit "CRD registration timed out."; fi
done

log "Installation complete! Monitor with: kubectl get pods -n awx"
