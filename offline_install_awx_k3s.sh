#!/bin/bash
# --- CONFIGURATION ---
REPO_SERVER="192.168.253.136"
VIP="192.168.253.145"
OPERATOR_VERSION="2.19.1"

set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log() { echo -e "\e[32m✔ $1\e[0m"; }

# 1. CLEANUP
log "Wiping previous failed state..."
kubectl delete awx awx-server -n awx --force --grace-period=0 2>/dev/null || true
kubectl delete deployment awx-operator-controller-manager -n awx 2>/dev/null || true

# 2. APPLY ALL CRDs (Prevents the "no matches for kind" errors)
log "Applying full CRD suite..."
# Since you are air-gapped, if you have the files locally, use 'kubectl apply -f <path>'
# Otherwise, we use the raw definition logic:
for crd in awxs awxbackups awxrestores awxmeshingresses; do
    kubectl apply -f "https://raw.githubusercontent.com/ansible/awx-operator/${OPERATOR_VERSION}/config/crd/bases/awx.ansible.com_${crd}.yaml" 2>/dev/null || \
    echo "Warning: Could not fetch ${crd} online. Ensure they are pre-loaded in your air-gap repo."
done

# 3. DEPLOY OPERATOR
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
        env:
          - name: ANSIBLE_DEBUG_LOGS
            value: "false"
EOF

# 4. DEPLOY AWX WITH HTTPS & AIR-GAP FIXES
log "Deploying AWX Instance (HTTPS Enabled)..."

cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: awx
spec:
  # Network - HTTPS
  service_type: loadbalancer
  # AWX generates a self-signed cert on 443 by default when service_type is LB
  
  # Air-Gap Protection
  auto_upgrade: false
  web_replicas: 1
  task_replicas: 1
  image_pull_policy: IfNotPresent
  
  # Image Registry Overrides (pointing to your local cache)
  control_plane_ee_image: quay.io/ansible/awx-ee:24.6.1
  ee_images:
    - name: "Local EE"
      image: quay.io/ansible/awx-ee:24.6.1

  # Database Security Fix
  postgres_extra_container_params:
    - name: postgres
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        fsGroup: 0
EOF

log "Deployment submitted. Watch for the Operator to stabilize first."
