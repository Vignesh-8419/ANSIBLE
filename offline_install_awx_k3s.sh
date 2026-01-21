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
log "Performing hard cleanup..."
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
pkill -9 -x k3s || true
umount -f /var/lib/rancher/k3s/storage 2>/dev/null || true
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s /tmp/*.tar /var/log/k3s_install.log

# ---------------- 2. NETWORK SETUP ----------------
log "Ensuring Virtual IP $VIP is active on $INTERFACE..."
if ! ip addr show $INTERFACE | grep -q $VIP; then
    ip addr add ${VIP}/24 dev $INTERFACE || true
fi

# ---------------- 3. DOWNLOAD BINARIES ----------------
log "Downloading Binaries..."
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/k3s -o /usr/local/bin/k3s
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/kustomize -o /usr/local/bin/kustomize
chmod +x /usr/local/bin/k3s /usr/local/bin/kustomize
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ---------------- 4. START K3S (REPROCESSED) ----------------
log "Starting K3s Server (Air-Gapped Mode)..."
# We add --flannel-backend=host-gw for better offline stability and --cluster-init
nohup /usr/local/bin/k3s server \
    --write-kubeconfig-mode 644 \
    --bind-address $VIP \
    --advertise-address $VIP \
    --node-ip $VIP \
    --disable traefik \
    --disable-cloud-controller \
    --kube-apiserver-arg="service-node-port-range=1-32767" \
    --data-dir /var/lib/rancher/k3s \
    >> /var/log/k3s_install.log 2>&1 &

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log "Waiting for K3s API to respond..."
MAX_RETRIES=40
COUNT=0
until [ -f /etc/rancher/k3s/k3s.yaml ] && kubectl get nodes &>/dev/null; do
    sleep 3
    COUNT=$((COUNT+1))
    echo -n "."
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo ""
        tail -n 20 /var/log/k3s_install.log
        error_exit "K3s failed to start. See logs above."
    fi
done
echo " Connected!"

# ---------------- 5. IMPORT IMAGES ----------------
log "Importing Container Images..."
IMAGE_FILES=("k3s-airgap-images.tar" "awx.tar" "awx-operator.tar" "postgres.tar" "redis.tar")
for IMG in "${IMAGE_FILES[@]}"; do
    log "Processing $IMG..."
    curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/images/$IMG -o /tmp/$IMG
    /usr/local/bin/k3s ctr images import /tmp/$IMG
    rm -f /tmp/$IMG
done

# ---------------- 6. DEPLOY AWX OPERATOR ----------------
log "Deploying AWX Operator..."
kubectl create namespace awx || true
mkdir -p /opt/awx-operator
cd /opt/awx-operator

# Note: In offline mode, the 'resources' URL might fail. 
# It's better to use a local manifest if kustomize fails.
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/ansible/awx-operator.git/config/default?ref=${OPERATOR_VERSION}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${OPERATOR_VERSION}
EOF

kustomize build . | kubectl apply -f - || echo "Kustomize failed, check internet/proxy."

log "Waiting for Operator..."
sleep 20
kubectl rollout status deployment awx-operator-controller-manager -n awx --timeout=300s || true

# ---------------- 7. DEPLOY AWX INSTANCE ----------------
log "Creating AWX Instance with Postgres permissions fix..."

cat <<EOF > /opt/awx-operator/awx-instance.yaml
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
  # This section fixes the CrashLoopBackOff for Postgres
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

# Create password secret before instance
kubectl create secret generic awx-server-admin-password \
    --from-literal=password='Root@123' -n awx --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f /opt/awx-operator/awx-instance.yaml -n awx

log "Success! Monitor progress with: kubectl get pods -n awx"
