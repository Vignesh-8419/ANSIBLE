#!/bin/bash

# --- CONFIGURATION ---
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
OPERATOR_VERSION="2.19.1"

set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log() { echo -e "\e[32m✔ $1\e[0m"; }

# 1. CLEANUP PREVIOUS ATTEMPTS
log "Cleaning up old deployment state..."
kubectl delete awx awx-server -n awx --force --grace-period=0 2>/dev/null || true
kubectl delete deployment awx-operator-controller-manager -n awx 2>/dev/null || true

# 2. APPLY ALL REQUIRED CRDs
log "Applying full CRD suite..."
# These must exist for the operator to stop 'kind' lookup errors
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
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: awxbackups.awx.ansible.com
spec:
  group: awx.ansible.com
  names:
    kind: AWXBackup
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
  name: awxrestores.awx.ansible.com
spec:
  group: awx.ansible.com
  names:
    kind: AWXRestore
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
  name: awxmeshingresses.awx.ansible.com
spec:
  group: awx.ansible.com
  names:
    kind: AWXMeshIngress
  scope: Namespaced
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        x-kubernetes-preserve-unknown-fields: true
EOF

# 3. RE-DEPLOY OPERATOR
log "Deploying Operator..."
kubectl create namespace awx 2>/dev/null || true

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
EOF

# 4. CREATE ADMIN PASSWORD SECRET
kubectl create secret generic awx-server-admin-password \
    --from-literal=password='Root@123' -n awx --dry-run=client -o yaml | kubectl apply -f -

# 5. DEPLOY AWX INSTANCE (HTTPS & AIR-GAP HARDENED)
log "Deploying AWX Instance..."

cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  # Network - Enable HTTPS via LoadBalancer
  service_type: loadbalancer
  ingress_type: none
  hostname: ${VIP}

  # Air-Gap Hardening (The most important part)
  auto_upgrade: false
  set_default_ee: false        # Don't try to pull default EEs from web
  web_replicas: 1
  task_replicas: 1
  image_pull_policy: IfNotPresent
  
  # Image Registry Overrides
  # Using the local quay.io mirror images you loaded
  control_plane_ee_image: quay.io/ansible/awx-ee:24.6.1
  ee_images:
    - name: "Local EE"
      image: quay.io/ansible/awx-ee:24.6.1

  # Database configuration
  postgres_init_container_resource_requirements:
    limits:
      cpu: "100m"
      memory: "128Mi"
    requests:
      cpu: "10m"
      memory: "64Mi"

  # Admin Account
  admin_user: admin
  admin_password_secret: awx-server-admin-password
EOF

log "SUCCESS: AWX Deployment initiated."
log "Monitor progress: kubectl get pods -n awx -w"
