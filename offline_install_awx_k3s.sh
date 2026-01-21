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

# ---------------- 1. CONFIGURE OFFLINE REPOS ----------------
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
log "Ensuring OS dependencies are installed..."
yum install -y psmisc socat conntrack-tools ipset-service || true

# ---------------- 2. NUCLEAR CLEANUP ----------------
log "Performing nuclear cleanup..."
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
pkill -9 -x k3s || true
pkill -9 -x containerd || true
cat /proc/mounts | grep -E 'k3s|kubelet' | awk '{print $2}' | sort -r | xargs -r umount -l || true
fuser -k 6443/tcp 2>/dev/null || true
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s /var/log/k3s_install.log

# ---------------- 3. NETWORK SETUP ----------------
log "Ensuring Virtual IP $VIP is active..."
if ! ip addr show $INTERFACE | grep -q $VIP; then
    ip addr add ${VIP}/24 dev $INTERFACE || true
fi

# ---------------- 4. DOWNLOAD BINARY ----------------
log "Downloading K3s..."
curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/binaries/k3s -o /usr/local/bin/k3s
chmod +x /usr/local/bin/k3s
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ---------------- 5. START K3S ----------------
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

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log "Waiting for K3s API..."
MAX_RETRIES=40
COUNT=0
until kubectl get nodes &>/dev/null; do
    sleep 3
    COUNT=$((COUNT+1))
    echo -n "."
    [ $COUNT -ge $MAX_RETRIES ] && error_exit "K3s failed to start."
done
echo " Connected!"

# ---------------- 6. IMPORT IMAGES ----------------
log "Importing Images..."
IMAGE_FILES=("k3s-airgap-images.tar" "awx.tar" "awx-operator.tar" "postgres.tar" "redis.tar")
for IMG in "${IMAGE_FILES[@]}"; do
    log "Processing $IMG..."
    curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/images/$IMG -o /tmp/$IMG
    k3s ctr images import /tmp/$IMG && rm -f /tmp/$IMG
done

# ---------------- 7. DEPLOY OPERATOR (INTERNAL YAML) ----------------
log "Deploying AWX Operator via direct apply..."
kubectl create namespace awx || true

# Since curl 404'd, we will use a "Local Kustomize" approach 
# If you have the awx-operator image, we can start it using a basic deployment
# This is a fallback manifest to get the operator running without external files

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: awx-operator-controller-manager
  namespace: awx
spec:
  replicas: 1
  selector:
    matchLabels:
      control-plane: controller-manager
  template:
    metadata:
      labels:
        control-plane: controller-manager
    spec:
      containers:
      - name: manager
        image: quay.io/ansible/awx-operator:${OPERATOR_VERSION}
        imagePullPolicy: IfNotPresent
        env:
          - name: WATCH_NAMESPACE
            value: "awx"
EOF

log "Waiting for Operator pod to initialize..."
sleep 20

# ---------------- 8. DEPLOY AWX INSTANCE ----------------
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
  hostname: ansible-server-01.vgs.com
  admin_user: admin
  admin_password_secret: awx-server-admin-password
  image: quay.io/ansible/awx
  image_version: ${AWX_VERSION}
  postgres_image: docker.io/library/postgres
  postgres_image_version: "15"
  postgres_extra_container_params:
    - name: postgres
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        fsGroup: 0
EOF

# Try applying. If CRD isn't ready, loop until it is.
MAX_WAIT=10
until kubectl apply -f /tmp/awx-instance.yaml -n awx 2>/dev/null; do
    echo "Waiting for AWX CustomResourceDefinition (CRD) to be registered by the operator..."
    sleep 10
    MAX_WAIT=$((MAX_WAIT-1))
    if [ $MAX_WAIT -eq 0 ]; then error_exit "Operator failed to register AWX CRD."; fi
done

log "Installation initiated! Access AWX at http://$VIP"
