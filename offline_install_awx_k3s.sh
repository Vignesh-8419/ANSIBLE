#!/bin/bash

# --- CONFIGURATION ---
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
INTERFACE="ens192"
AWX_VERSION="24.6.1"
OPERATOR_VERSION="2.19.1"

set -e

log() {
    echo -e "\e[32m✔ $1\e[0m"
}

error_exit() {
    echo -e "\e[31m✘ $1\e[0m"
    exit 1
}

# ---------------- 1. NUCLEAR CLEANUP ----------------
log "Performing nuclear cleanup of existing mounts and processes..."
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
pkill -9 -x k3s || true
pkill -9 -x containerd || true

# Clean up all lingering mounts
cat /proc/mounts | grep -E 'k3s|kubelet' | awk '{print $2}' | sort -r | xargs -r umount -l || true

# Force release port 6443
fuser -k 6443/tcp 2>/dev/null || true

# Wipe directories
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s /tmp/*.tar /var/log/k3s_install.log

# ---------------- 2. NETWORK SETUP ----------------
log "Ensuring Virtual IP $VIP is active..."
if ! ip addr show $INTERFACE | grep -q $VIP; then
    ip addr add ${VIP}/24 dev $INTERFACE || true
fi

# ---------------- 3. DOWNLOAD BINARIES ----------------
log "Downloading Binaries..."
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/k3s -o /usr/local/bin/k3s
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/kustomize -o /usr/local/bin/kustomize
chmod +x /usr/local/bin/k3s /usr/local/bin/kustomize
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ---------------- 4. START K3S (BACKGROUND) ----------------
log "Starting K3s Server..."
nohup /usr/local/bin/k3s server \
    --write-kubeconfig-mode 644 \
    --bind-address $VIP \
    --advertise-address $VIP \
    --node-ip $VIP \
    --disable traefik \
    --kube-apiserver-arg="service-node-port-range=1-32767" \
    --data-dir /var/lib/rancher/k3s \
    >> /var/log/k3s_install.log 2>&1 &

log "Waiting for K3s API to respond..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
MAX_RETRIES=40
COUNT=0
until kubectl get nodes &>/dev/null; do
    sleep 3
    COUNT=$((COUNT+1))
    echo -n "."
    [ $COUNT -ge $MAX_RETRIES ] && error_exit "K3s failed to start. Port 6443 may still be locked."
done
echo " Connected!"

# ---------------- 5. IMPORT IMAGES ----------------
log "Importing Images..."
IMAGE_FILES=("k3s-airgap-images.tar" "awx.tar" "awx-operator.tar" "postgres.tar" "redis.tar")
for IMG in "${IMAGE_FILES[@]}"; do
    log "Processing $IMG..."
    curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/images/$IMG -o /tmp/$IMG
    k3s ctr images import /tmp/$IMG && rm -f /tmp/$IMG
done

# ---------------- 6. DEPLOY OPERATOR ----------------
log "Deploying AWX Operator..."
kubectl create namespace awx || true
mkdir -p /opt/awx-operator
cd /opt/awx-operator

cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/ansible/awx-operator.git/config/default?ref=${OPERATOR_VERSION}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${OPERATOR_VERSION}
EOF

kustomize build . | kubectl apply -f - || true
sleep 30

# ---------------- 7. DEPLOY AWX INSTANCE ----------------
log "Creating AWX Instance with Storage & LoadBalancer fixes..."

# Create Admin Password Secret
kubectl create secret generic awx-server-admin-password \
    --from-literal=password='Root@123' -n awx --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  service_type: loadbalancer
  hostname: ansible-server-01.vgs.com
  admin_user: admin
  admin_password_secret: awx-server-admin-password
  image: quay.io/ansible/awx
  image_version: ${AWX_VERSION}
  postgres_image: docker.io/library/postgres
  postgres_image_version: "15"
  # This section fixes the CrashLoopBackOff for Postgres permissions
  postgres_extra_container_params:
    - name: postgres
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        fsGroup: 0
EOF

kubectl apply -f awx-instance.yaml -n awx

log "Installation initiated! Check progress with: kubectl get pods -n awx"
