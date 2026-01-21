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

# ---------------- 1. START K3S (SKIP RE-INSTALL IF RUNNING) ----------------
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get nodes &>/dev/null; then
    log "K3s not responding, restarting..."
    systemctl stop k3s 2>/dev/null || true
    pkill -9 -x k3s || true
    nohup /usr/local/bin/k3s server --write-kubeconfig-mode 644 --bind-address $VIP --advertise-address $VIP --node-ip $VIP --disable traefik --data-dir /var/lib/rancher/k3s >> /var/log/k3s_install.log 2>&1 &
    sleep 10
fi

# ---------------- 2. APPLY CRDs (THE MISSING PIECE) ----------------
log "Applying AWX Custom Resource Definitions..."

cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: awxs.awx.ansible.com
spec:
  group: awx.ansible.com
  names:
    kind: AWX
    listKind: AWXList
    plural: awxs
    singular: awx
  scope: Namespaced
  versions:
  - name: v1beta1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        x-kubernetes-preserve-unknown-fields: true
    subresources:
      status: {}
EOF

# ---------------- 3. RE-DEPLOY OPERATOR & RBAC ----------------
log "Ensuring Operator Permissions & Deployment..."
kubectl create namespace awx 2>/dev/null || true

cat <<EOF | kubectl apply -f -
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
EOF

# ---------------- 4. DEPLOY AWX INSTANCE ----------------
log "Deploying AWX Instance..."

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

log "Waiting for API to recognize AWX type..."
sleep 10
kubectl apply -f /tmp/awx-instance.yaml -n awx

log "SUCCESS: AWX Deployment initiated."
log "Monitor progress with: kubectl get pods -n awx"
