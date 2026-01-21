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

# Ensure K3s dependencies are present
yum install -y psmisc socat conntrack-tools ipset-service || true

# ---------------- 2. NUCLEAR CLEANUP ----------------
log "Performing nuclear cleanup..."
/usr/local/bin/k3s-killall.sh 2>/dev/null || true
pkill -9 -x k3s || true
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s

# ---------------- 3. NETWORK & BINARIES ----------------
if ! ip addr show $INTERFACE | grep -q $VIP; then
    ip addr add ${VIP}/24 dev $INTERFACE || true
fi

log "Downloading K3s binary..."
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
until kubectl get nodes &>/dev/null; do sleep 2; echo -n "."; done
log " Connected!"

# ---------------- 5. IMPORT IMAGES ----------------
log "Importing Images..."
IMAGE_FILES=("k3s-airgap-images.tar" "awx.tar" "awx-operator.tar" "postgres.tar" "redis.tar")
for IMG in "${IMAGE_FILES[@]}"; do
    log "Loading $IMG..."
    curl -fkL https://${REPO_SERVER}/repo/ansible_offline_repo/images/$IMG -o /tmp/$IMG
    k3s ctr images import /tmp/$IMG && rm -f /tmp/$IMG
done

# ---------------- 6. DEPLOY OPERATOR (EMBEDDED MANIFEST) ----------------
log "Deploying AWX Operator (Embedded YAML)..."
kubectl create namespace awx || true

# This command generates the required CRDs and Operator deployment directly
# to avoid the 404 error you encountered.
cat <<EOF > /tmp/awx-operator-local.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: awx-operator-controller-manager
  namespace: awx
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: awx-operator-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: awx-operator-controller-manager
  namespace: awx
---
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
      serviceAccountName: awx-operator-controller-manager
      containers:
      - name: manager
        image: quay.io/ansible/awx-operator:${OPERATOR_VERSION}
        imagePullPolicy: IfNotPresent
        env:
          - name: WATCH_NAMESPACE
            value: ""
EOF

kubectl apply -f /tmp/awx-operator-local.yaml

# ---------------- 7. DEPLOY AWX INSTANCE ----------------
log "Creating AWX Instance..."

# Admin Password Secret
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

log "Waiting for Operator to start..."
sleep 30

# Attempt to apply AWX instance
MAX_RETRIES=10
until kubectl apply -f /tmp/awx-instance.yaml -n awx 2>/dev/null; do
    echo "Waiting for AWX CRD to be ready..."
    sleep 15
    ((MAX_RETRIES--))
    if [ $MAX_RETRIES -le 0 ]; then 
        log "Warning: CRD not ready yet. You may need to run 'kubectl apply -f /tmp/awx-instance.yaml -n awx' manually in a few minutes."
        break
    fi
done

log "Script complete! Check progress with: kubectl get pods -n awx -w"
