=#!/bin/bash

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

# ---------------- 1. HARD CLEANUP ----------------
log "Performing hard cleanup of previous attempts..."
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
pkill -9 -x k3s || true
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s /tmp/*.tar
rm -rf /var/lib/rancher/k3s/agent/containerd 2>/dev/null || true

# ---------------- 2. NETWORK SETUP ----------------
log "Ensuring Virtual IP $VIP is active..."
if ! ip addr show $INTERFACE | grep -q $VIP; then
    ip addr add ${VIP}/24 dev $INTERFACE || true
fi

# ---------------- 3. DOWNLOAD BINARIES ----------------
log "Downloading K3s and Kustomize binaries..."
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/k3s -o /usr/local/bin/k3s
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/kustomize -o /usr/local/bin/kustomize
chmod +x /usr/local/bin/k3s /usr/local/bin/kustomize
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ---------------- 4. START K3S (BACKGROUND) ----------------
log "Starting K3s Server..."
# Note: We keep your background execution but add the port-range flag just in case
k3s server --write-kubeconfig-mode 644 \
    --bind-address $VIP \
    --advertise-address $VIP \
    --node-ip $VIP \
    --disable traefik \
    --kube-apiserver-arg="service-node-port-range=1-32767" \
    --data-dir /var/lib/rancher/k3s \
    >> /var/log/k3s_install.log 2>&1 &

log "Waiting for K3s API to respond..."
MAX_RETRIES=30
COUNT=0
until kubectl get nodes &>/dev/null; do
    sleep 5
    COUNT=$((COUNT+1))
    [ $COUNT -ge $MAX_RETRIES ] && error_exit "K3s failed to start."
    echo -n "."
done
echo " Connected!"

# ---------------- 5. IMPORT IMAGES ----------------
log "Fetching and Importing Container Images..."
IMAGE_FILES=("k3s-airgap-images.tar" "awx.tar" "awx-operator.tar" "postgres.tar" "redis.tar")
for IMG in "${IMAGE_FILES[@]}"; do
    log "Processing $IMG..."
    curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/images/$IMG -o /tmp/$IMG
    k3s ctr images import /tmp/$IMG
    rm -f /tmp/$IMG
done

# ---------------- 6. DEPLOY AWX OPERATOR ----------------
log "Deploying AWX Operator..."
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

kustomize build . | kubectl apply -f - || log "Warning: Kustomize build failed."
sleep 15

# ---------------- 7. SET ADMIN PASSWORD ----------------
log "Setting Admin Password..."
kubectl create secret generic awx-server-admin-password \
    --from-literal=password='Root@123' -n awx --dry-run=client -o yaml | kubectl apply -f -

# ---------------- 8. DEPLOY AWX INSTANCE (WITH POSTGRES FIX) ----------------
log "Creating AWX Instance with Fixes..."



cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  # Networking Fix: Use loadbalancer to get port 80/443 directly
  service_type: loadbalancer
  hostname: ansible-server-01.vgs.com
  
  # Credentials
  admin_user: admin
  admin_password_secret: awx-server-admin-password

  # Image Config
  image: quay.io/ansible/awx
  image_version: ${AWX_VERSION}
  
  # Postgres Fix: Prevent 'chmod' permission errors on data dir
  postgres_image: docker.io/library/postgres
  postgres_image_version: "15"
  postgres_configuration_parameters:
    - "max_connections=100"
  postgres_extra_container_params:
    - name: postgres
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        fsGroup: 0

  redis_image: docker.io/library/redis
  redis_image_version: "7"
  control_plane_ee_image: quay.io/ansible/awx-ee:latest
EOF

kubectl apply -f awx-instance.yaml -n awx

log "Installation initiated!"
log "1. Monitor Postgres: kubectl get pods -n awx -w"
log "2. Access AWX: https://$VIP (Username: admin / Password: Root@123)"
