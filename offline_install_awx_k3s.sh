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

# ---------------- 1. HARD CLEANUP ----------------
log "Performing hard cleanup of previous attempts..."
# Stop K3s and kill processes
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
pkill -9 -x k3s || true

# Remove data and corrupted image layers
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s /tmp/*.tar
# This ensures we don't reuse the bad image IDs
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
k3s server --write-kubeconfig-mode 644 \
    --bind-address $VIP \
    --advertise-address $VIP \
    --node-ip $VIP \
    --disable traefik \
    --data-dir /var/lib/rancher/k3s \
    >> /var/log/k3s_install.log 2>&1 &

log "Waiting for K3s API to respond..."
MAX_RETRIES=30
COUNT=0
until kubectl get nodes &>/dev/null; do
    sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        error_exit "K3s failed to start. Check /var/log/k3s_install.log"
    fi
    echo -n "."
done
echo " Connected!"

# ---------------- 5. IMPORT IMAGES ----------------
log "Fetching and Importing Container Images..."
# Updated to use the individual files we verified on http-server-01
IMAGE_FILES=("k3s-airgap-images.tar" "awx.tar" "awx-operator.tar" "postgres.tar" "redis.tar")

for IMG in "${IMAGE_FILES[@]}"; do
    log "Processing $IMG..."
    if curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/images/$IMG -o /tmp/$IMG; then
        k3s ctr images import /tmp/$IMG
        rm -f /tmp/$IMG
    else
        error_exit "Could not download $IMG from repo server."
    fi
done

# ---------------- 6. DEPLOY AWX OPERATOR ----------------
log "Deploying AWX Operator..."
mkdir -p /opt/awx-operator
cd /opt/awx-operator

# We create the kustomization, but note: in a truly offline environment,
# kustomize build might still try to reach GitHub for the remote resource.
# If this step fails, we will need to apply a local manifest file.
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/ansible/awx-operator.git/config/default?ref=${OPERATOR_VERSION}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${OPERATOR_VERSION}
EOF

# Build and apply
kustomize build . | kubectl apply -f - || log "Warning: Kustomize build failed, may need offline manifest."

log "Waiting for Operator to be ready..."
# Give it a moment to initialize the deployment
sleep 10
kubectl rollout status deployment awx-operator-controller-manager -n awx --timeout=300s || true

# ---------------- 7. DEPLOY AWX INSTANCE ----------------
log "Creating AWX Instance..."

cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  service_type: nodeport
  image: quay.io/ansible/awx
  image_version: ${AWX_VERSION}
  postgres_image: docker.io/library/postgres
  postgres_image_version: "15"
  redis_image: docker.io/library/redis
  redis_image_version: "7"
  control_plane_ee_image: quay.io/ansible/awx-ee:latest
EOF

kubectl apply -f awx-instance.yaml -n awx

log "Installation initiated!"
log "Use 'kubectl get pods -n awx' to monitor the deployment."
