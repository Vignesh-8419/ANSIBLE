#!/bin/bash
set -euo pipefail

###############################################################################
# AWX Production Setup - LATEST STABLE (2.19.1) WITH PERMISSION FIX
###############################################################################

AWX_NAMESPACE="awx"
AWX_NAME="awx-prod"
AWX_OPERATOR_VERSION="2.19.1"
AWX_HOSTNAME="awx-server-01.vgs.com"

# Nodes
CONTROL_NODE_IP="192.168.253.135"
WORKER_NODE_IPS=("192.168.253.136" "192.168.253.137")
WORKERS=("awx-work-node-01.vgs.com" "awx-work-node-02.vgs.com")

SSH_USER="root"
SSH_PASS="Root@123"

# MetalLB Config
METALLB_POOL_START="192.168.253.220"
METALLB_POOL_END="192.168.253.230"

echo "=== STARTING FULL 15-TASK DEPLOYMENT (v${AWX_OPERATOR_VERSION}) ==="

# 1. Cleanup Environment
echo "==> Task 1/15: Cleaning up previous failed attempts..."
kubectl delete awx --all -n $AWX_NAMESPACE --ignore-not-found || true
kubectl delete ns $AWX_NAMESPACE --timeout=60s --ignore-not-found || true

# 2. Labeling Nodes
echo "==> Task 2/15: Labeling nodes for storage and workloads..."
kubectl label nodes "${WORKERS[@]}" nodepool=workloads --overwrite || true
kubectl label nodes "${WORKERS[@]}" longhorn=storage --overwrite || true

# 3. Kernel & iSCSI Prep
echo "==> Task 3/15: Preparing iSCSI and Kernel modules on all nodes..."
for NODE_IP in "$CONTROL_NODE_IP" "${WORKER_NODE_IPS[@]}"; do
  sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${NODE_IP} "
    yum install -y iscsi-initiator-utils nfs-utils
    systemctl enable --now iscsid
    modprobe br_netfilter overlay
  "
done

# 4. Networking (Flannel)
echo "==> Task 4/15: Deploying Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.25.2/kube-flannel.yml

# 5. Ingress Controller
echo "==> Task 5/15: Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
kubectl -n ingress-nginx wait --for=condition=Available deployment/ingress-nginx-controller --timeout=300s

# 6. MetalLB (LoadBalancer Stack)
echo "==> Task 6/15: Deploying MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl -n metallb-system wait --for=condition=Available deployment/controller --timeout=300s

# 7. MetalLB IP Pool
echo "==> Task 7/15: Configuring MetalLB IP Address Pool..."
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: awx-static-pool
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_POOL_START}-${METALLB_POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: awx-l2-adv
  namespace: metallb-system
EOF

# 8. Cert-Manager
echo "==> Task 8/15: Deploying Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=300s

# 9. Longhorn Storage
echo "==> Task 9/15: Deploying Longhorn Storage..."
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace --set defaultSettings.defaultReplicaCount=1
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 10. AWX Operator (UPGRADED VERSION)
echo "==> Task 10/15: Installing AWX Operator ${AWX_OPERATOR_VERSION}..."
kubectl create ns ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator && git checkout ${AWX_OPERATOR_VERSION}
kubectl apply -k config/default -n ${AWX_NAMESPACE}
kubectl -n ${AWX_NAMESPACE} rollout status deployment awx-operator-controller-manager --timeout=300s

# 11. AWX Admin Secrets
echo "==> Task 11/15: Creating Admin Secrets..."
kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password --from-literal=password='Root@123' --dry-run=client -o yaml | kubectl apply -f -

# 12. AWX Instance Deployment (WITH GOOGLE FIX)
echo "==> Task 12/15: Deploying AWX with postgres_data_volume_init..."
cat <<EOF | kubectl apply -n ${AWX_NAMESPACE} -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: NodePort      # <--- CHANGE THIS FROM ClusterIP TO NodePort
  ingress_type: ingress
  hostname: ${AWX_HOSTNAME}
  admin_password_secret: awx-admin-password
  postgres_storage_class: longhorn
  postgres_data_volume_init: true
  postgres_resource_requirements:
    requests: { cpu: "500m", memory: "2Gi" }
    limits: { cpu: "2", memory: "4Gi" }
EOF

# 13. Stability Check for Postgres
echo "==> Task 13/15: Waiting for Postgres and breaking Longhorn locks if needed..."
until kubectl get pvc -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=database" | grep -i Bound; do sleep 5; done
PV_NAME=$(kubectl get pvc -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=database" -o jsonpath='{.items[0].spec.volumeName}')

# This loop ensures the volume actually attaches by clearing any stuck nodeIDs
for i in {1..5}; do
  kubectl patch lhv "$PV_NAME" -n longhorn-system --type=merge -p '{"spec":{"nodeID":""}}' 2>/dev/null || true
  sleep 10
  if kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=database" | grep -E "Running|Init"; then
    break
  fi
done

# 14. Watch Migration (UPDATED FIX)
echo "==> Task 14/15: Watching Database Migration..."
# Wait for any pod that has the "migration" label to appear
until kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" | grep -v "No resources found" >/dev/null 2>&1; do
  echo "Waiting for migration pod to be created..."
  sleep 10
done

# Get the actual name of the migration pod (whatever version it is)
MIGRATION_POD=$(kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" -o jsonpath='{.items[0].metadata.name}')

echo "Streaming logs from migration pod: $MIGRATION_POD"
kubectl logs -f "$MIGRATION_POD" -n ${AWX_NAMESPACE}

# 15. Final Health Check
echo "==> Task 15/15: Final Service Check..."
kubectl get pods -n ${AWX_NAMESPACE}
echo "-----------------------------------------------------------------------"
echo "AWX Installation Complete!"
echo "URL: http://${AWX_HOSTNAME}"
echo "Admin Username: admin"
echo "Admin Password: Root@123"
echo "-----------------------------------------------------------------------"

Run the edit command:

Bash

kubectl edit svc awx-prod-service -n awx
Modify the file: Find the line that says type: ClusterIP and change it to type: NodePort. Save and exit (:wq).
