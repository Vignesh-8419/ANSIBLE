#!/bin/bash
set -euo pipefail

###############################################################################
# AWX Production Setup - LATEST STABLE (2.19.1) WITH SSL & LOADBALANCER FIXES
###############################################################################

AWX_NAMESPACE="awx"
AWX_NAME="awx-prod"
AWX_OPERATOR_VERSION="2.19.1"
AWX_HOSTNAME="awx-server-01.vgs.com"
LB_IP="192.168.253.225"

# Nodes
CONTROL_NODE_IP="192.168.253.135"
WORKER_NODE_IPS=("192.168.253.136" "192.168.253.137")
WORKERS=("awx-work-node-01.vgs.com" "awx-work-node-02.vgs.com")

SSH_USER="root"
SSH_PASS="Root@123"

# MetalLB Config
METALLB_POOL_START="192.168.253.220"
METALLB_POOL_END="192.168.253.230"

echo "install req package"
dnf install -y sshpass

echo "=== STARTING FULL 18-TASK DEPLOYMENT (v${AWX_OPERATOR_VERSION}) ==?"

# 1. Cleanup Environment
echo "==> Task 1/18: Cleaning up previous failed attempts..."
kubectl delete awx --all -n $AWX_NAMESPACE --ignore-not-found || true
kubectl delete ns $AWX_NAMESPACE --timeout=60s --ignore-not-found || true

# 2. Labeling Nodes
echo "==> Task 2/18: Labeling nodes for storage and workloads..."
kubectl label nodes "${WORKERS[@]}" nodepool=workloads --overwrite || true
kubectl label nodes "${WORKERS[@]}" longhorn=storage --overwrite || true

# 3. Kernel & iSCSI Prep
echo "==> Task 3/18: Preparing iSCSI and Kernel modules on all nodes..."
for NODE_IP in "$CONTROL_NODE_IP" "${WORKER_NODE_IPS[@]}"; do
  sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${NODE_IP} "
    yum install -y iscsi-initiator-utils nfs-utils
    systemctl enable --now iscsid
    modprobe br_netfilter overlay
  "
done

# 4. Networking (Flannel) - WITH IMMUTABLE FIELD FIX
echo "==> Task 4/18: Deploying Flannel CNI..."
kubectl delete ds kube-flannel-ds -n kube-flannel --ignore-not-found || true
kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.25.2/kube-flannel.yml

# 5. Ingress Controller
echo "==> Task 5/18: Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
kubectl -n ingress-nginx wait --for=condition=Available deployment/ingress-nginx-controller --timeout=300s

# 6. MetalLB (LoadBalancer Stack)
echo "==> Task 6/18: Deploying MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl -n metallb-system wait --for=condition=Available deployment/controller --timeout=300s

# 7. MetalLB IP Pool
echo "==> Task 7/18: Configuring MetalLB IP Address Pool..."
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
echo "==> Task 8/18: Deploying Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=300s

# 9. Longhorn Storage
echo "==> Task 9/18: Deploying Longhorn Storage..."
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace --set defaultSettings.defaultReplicaCount=1
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 10. AWX Operator
echo "==> Task 10/18: Installing AWX Operator ${AWX_OPERATOR_VERSION}..."
kubectl create ns ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator && git checkout ${AWX_OPERATOR_VERSION}
kubectl apply -k config/default -n ${AWX_NAMESPACE}
kubectl -n ${AWX_NAMESPACE} rollout status deployment awx-operator-controller-manager --timeout=300s

# 11. AWX Admin Secrets
echo "==> Task 11/18: Creating Admin Secrets..."
kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password --from-literal=password='Root@123' --dry-run=client -o yaml | kubectl apply -f -

# 12. AWX Instance Deployment
echo "==> Task 12/18: Deploying AWX Instance..."
cat <<EOF | kubectl apply -n ${AWX_NAMESPACE} -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: NodePort
  ingress_type: ingress
  hostname: ${AWX_HOSTNAME}
  ingress_tls_secret: awx-server-tls-secret
  admin_password_secret: awx-admin-password
  postgres_storage_class: longhorn
  postgres_data_volume_init: true
  postgres_resource_requirements:
    requests:
      cpu: "500m"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
EOF

# 13. Stability Check for Postgres
echo "==> Task 13/18: Waiting for Postgres..."
until kubectl get pvc -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=database" | grep -i Bound; do sleep 5; done

# 14. Watch Migration
echo "==> Task 14/18: Watching Database Migration..."
until kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" | grep -v "No resources found" >/dev/null 2>&1; do
  sleep 10
done
MIGRATION_POD=$(kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f "$MIGRATION_POD" -n ${AWX_NAMESPACE}

# 15. Ingress Controller External IP (Front Door)
echo "==> Task 15/18: Mapping Static IP to Ingress Controller..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\": {\"type\": \"LoadBalancer\", \"loadBalancerIP\": \"$LB_IP\"}}"

# 16. Patch Ingress Class
echo "==> Task 16/18: Patching Ingress Class for NGINX..."
until kubectl get ingress ${AWX_NAME}-ingress -n ${AWX_NAMESPACE} >/dev/null 2>&1; do sleep 5; done
kubectl patch ingress ${AWX_NAME}-ingress -n ${AWX_NAMESPACE} -p '{"spec": {"ingressClassName": "nginx"}}'

# 17. Create SSL Issuer
echo "==> Task 17/18: Creating SSL Issuer..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: awx-selfsigned-issuer
spec:
  selfSigned: {}
EOF

# 18. Generate Certificate
echo "==> Task 18/18: Generating SSL Certificate..."
cat <<EOF | kubectl apply -n ${AWX_NAMESPACE} -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: awx-server-cert
spec:
  secretName: awx-server-tls-secret
  dnsNames:
  - ${AWX_HOSTNAME}
  issuerRef:
    name: awx-selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
EOF

echo "-----------------------------------------------------------------------"
echo "AWX Installation Complete!"
echo "URL: https://${AWX_HOSTNAME}"
echo "IP: ${LB_IP}"
echo "Admin Username: admin"
echo "Admin Password: Root@123"
echo "-----------------------------------------------------------------------"
