#!/bin/bash

# --- CONFIGURATION ---
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
OPERATOR_VERSION="2.19.1"

set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log() { echo -e "\e[32m✔ $1\e[0m"; }

# 1. CLEANUP
log "Cleaning up old state..."
kubectl delete awx awx-server -n awx --force --grace-period=0 2>/dev/null || true
kubectl delete deployment awx-operator-controller-manager -n awx 2>/dev/null || true
sleep 5

# 2. APPLY ALL CRDs (With plurals to avoid previous error)
log "Applying CRDs..."
cat <<EOF | kubectl apply -f -
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

# 3. DEPLOY OPERATOR WITH OFFLINE ENV VARS
log "Deploying Operator with Air-Gap Settings..."
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
          # This stops the internal Ansible from trying to reach out
          - name: ANSIBLE_GATHERING
            value: "explicit"
          - name: ANSIBLE_CALLBACK_WHITELIST
            value: "profile_tasks"
          - name: WATCH_NAMESPACE
            value: "awx"
EOF

# 4. DEPLOY AWX INSTANCE (HTTPS & OFFLINE)
log "Deploying AWX Instance (HTTPS Enabled)..."
# Re-ensure secret exists
kubectl create secret generic awx-server-admin-password --from-literal=password='Root@123' -n awx --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  # Networking
  service_type: loadbalancer
  ingress_type: none
  hostname: ${VIP}

  # Air-Gap Hardening
  auto_upgrade: false
  set_default_ee: false
  web_replicas: 1
  task_replicas: 1
  image_pull_policy: IfNotPresent
  
  # Explicit Image Overrides (Prevents metadata lookups)
  control_plane_ee_image: quay.io/ansible/awx-ee:24.6.1
  redis_image: docker.io/library/redis:7
  postgres_image: quay.io/sclorg/postgresql-15-c9s:latest
  
  ee_images:
    - name: "Local EE"
      image: quay.io/ansible/awx-ee:24.6.1

  # Resource limits to prevent OOM kills
  postgres_resource_requirements:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"

  admin_user: admin
  admin_password_secret: awx-server-admin-password
EOF

log "SUCCESS: Deployment initiated."
log "Watch with: kubectl logs -f -n awx deployment/awx-operator-controller-manager"
