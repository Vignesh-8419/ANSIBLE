#!/bin/bash

# --- CONFIGURATION ---
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
OPERATOR_VERSION="2.19.1"

# --- AUTO-DETECT KUBECONFIG ---
if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    K_PATH="/etc/rancher/k3s/k3s.yaml"
elif [ -f "/etc/kubernetes/admin.conf" ]; then
    K_PATH="/etc/kubernetes/admin.conf"
elif [ -f "$HOME/.kube/config" ]; then
    K_PATH="$HOME/.kube/config"
else
    echo "❌ ERROR: Could not find k3s.yaml or admin.conf. Is K3s installed?"
    exit 1
fi

K_CMD="kubectl --kubeconfig=$K_PATH"
set -e

log() { echo -e "\e[32m✔ $1\e[0m"; }

log "Using Kubeconfig at: $K_PATH"

# 1. CLEANUP
log "Cleaning up old state..."
$K_CMD delete awx awx-server -n awx --force --grace-period=0 2>/dev/null || true
$K_CMD delete deployment awx-operator-controller-manager -n awx 2>/dev/null || true
sleep 2

# 2. APPLY CRDs
log "Applying CRDs (Validation Disabled)..."
cat <<EOF | $K_CMD apply --validate=false -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: awxs.awx.ansible.com
spec:
  group: awx.ansible.com
  names:
    kind: AWX
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
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: awxbackups.awx.ansible.com
spec:
  group: awx.ansible.com
  names:
    kind: AWXBackup
    plural: awxbackups
    singular: awxbackup
  scope: Namespaced
  versions:
  - name: v1beta1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        x-kubernetes-preserve-unknown-fields: true
EOF

# 3. DEPLOY OPERATOR
log "Deploying Operator..."
$K_CMD create namespace awx 2>/dev/null || true

cat <<EOF | $K_CMD apply -f -
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
          - name: ANSIBLE_GATHERING
            value: "explicit"
          - name: WATCH_NAMESPACE
            value: "awx"
EOF

# 4. DEPLOY AWX
log "Deploying AWX Instance (HTTPS Enabled)..."
$K_CMD create secret generic awx-server-admin-password --from-literal=password='Root@123' -n awx --dry-run=client -o yaml | $K_CMD apply -f -

cat <<EOF | $K_CMD apply --validate=false -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  service_type: loadbalancer
  ingress_type: none
  hostname: ${VIP}
  auto_upgrade: false
  set_default_ee: false
  web_replicas: 1
  task_replicas: 1
  image_pull_policy: IfNotPresent
  control_plane_ee_image: quay.io/ansible/awx-ee:24.6.1
  redis_image: docker.io/library/redis:7
  postgres_image: quay.io/sclorg/postgresql-15-c9s:latest
  ee_images:
    - name: "Local EE"
      image: quay.io/ansible/awx-ee:24.6.1
  admin_user: admin
  admin_password_secret: awx-server-admin-password
EOF

log "SUCCESS: Deployment initiated."
