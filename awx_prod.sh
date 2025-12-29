#!/bin/bash
set -euo pipefail

###############################################################################
# AWX Production Setup (Ingress + TLS + Longhorn Storage)
###############################################################################

# --- Config ---
AWX_NAMESPACE="awx"
AWX_NAME="awx-prod"
AWX_OPERATOR_VERSION="2.7.2"
AWX_HOSTNAME="awx-server-01.vgs.com"
EMAIL_ACME="infra-team@vgs.com"

# Nodes
CONTROL_NODE_IP="192.168.253.135"
WORKER_NODE_IPS=("192.168.253.136" "192.168.253.137")
WORKERS=("awx-work-node-01.vgs.com" "awx-work-node-02.vgs.com")

SSH_USER="root"
SSH_PASS="Root@123"

# MetalLB address pool
METALLB_POOL_START="192.168.253.220"
METALLB_POOL_END="192.168.253.230"
METALLB_IP_RESERVE="192.168.253.225"

# Required pkgs
echo "==> Checking system dependencies..."
for pkg in git curl sshpass; do
    if ! command -v $pkg &> /dev/null; then
        echo "Installing $pkg..."
        yum install -y $pkg
    fi
done

echo "=== AWX PRODUCTION SETUP STARTED ==="

###############################################################################
# 1. Node Prep & Labels
###############################################################################
echo "==> Task 1/15: Labeling nodes..."
kubectl label nodes "${WORKERS[@]}" nodepool=workloads --overwrite || true
kubectl label nodes "${WORKERS[@]}" longhorn=storage --overwrite || true

###############################################################################
# 2. Storage Dependencies (iSCSI/NFS)
###############################################################################
echo "==> Task 2/15: Installing storage dependencies on all nodes..."
for NODE_IP in "$CONTROL_NODE_IP" "${WORKER_NODE_IPS[@]}"; do
  sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${NODE_IP} '
    if command -v yum >/dev/null 2>&1; then
      yum install -y iscsi-initiator-utils nfs-utils
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get update && apt-get install -y open-iscsi nfs-common
    fi
    systemctl enable --now iscsid
  '
done

###############################################################################
# 3. Kernel & Network Tuning
###############################################################################
echo "==> Task 3/15: Tuning kernel modules..."
for NODE_IP in "${WORKER_NODE_IPS[@]}"; do
  sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${NODE_IP} '
    modprobe br_netfilter overlay
    sysctl -w net.ipv4.ip_forward=1
    sysctl --system || true
  '
done

###############################################################################
# 4. Firewall Prep
###############################################################################
echo "==> Task 4/15: Stopping firewalls..."
sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${CONTROL_NODE_IP} 'systemctl stop firewalld.service || true'

###############################################################################
# 5. Networking (Flannel)
###############################################################################
echo "==> Task 5/15: Applying Flannel CNI..."
# Force delete the existing DaemonSet to avoid immutable field errors
kubectl delete daemonset kube-flannel-ds -n kube-flannel --ignore-not-found

# Apply the new manifest
kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.25.2/kube-flannel.yml

# Wait for rollout
kubectl -n kube-flannel rollout status daemonset kube-flannel-ds --timeout=300s

###############################################################################
# 6. Kube-Proxy Refresh
###############################################################################
echo "==> Task 6/15: Recycling kube-proxy..."
for NODE in "${WORKERS[@]}"; do
  kubectl -n kube-system delete pod $(kubectl -n kube-system get pods -o wide | awk "/${NODE}/ && /kube-proxy/ {print \$1}") || true
done

###############################################################################
# 7. Ingress Controller
###############################################################################
echo "==> Task 7/15: Installing NGINX Ingress..."
kubectl create ns ingress-nginx || true
kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
kubectl -n ingress-nginx rollout status deployment ingress-nginx-controller --timeout=300s


###############################################################################
# 8. Load Balancer (MetalLB)
###############################################################################
echo "==> Task 8/15: Configuring MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-frr.yaml

# NEW: Wait for the controller to be ready so the Webhook is live
echo "Waiting for MetalLB controller to be ready..."
kubectl -n metallb-system wait --for=condition=Available deployment/controller --timeout=300s

# NEW: Wait for the speaker pods (daemonset) to be ready
echo "Waiting for MetalLB speakers to be ready..."
kubectl -n metallb-system rollout status daemonset/speaker --timeout=300s

# Give the webhook service an extra 5 seconds to settle
sleep 5

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: awx-lb-pool
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_POOL_START}-${METALLB_POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: awx-l2
  namespace: metallb-system
EOF

# Apply the fixed IP to the Ingress controller
kubectl -n ingress-nginx patch svc ingress-nginx-controller -p '{"spec":{"type":"LoadBalancer","loadBalancerIP":"'${METALLB_IP_RESERVE}'"}}'

###############################################################################
# 9. Certificate Management
###############################################################################
echo "==> Task 9/15: Configuring Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=300s
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${EMAIL_ACME}
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers: [{ "http01": { "ingress": { "class": "nginx" } } }]
EOF

###############################################################################
# 0. Ensure Helm is installed
###############################################################################
if ! command -v helm &> /dev/null; then
    echo "==> Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

###############################################################################
# 10. Longhorn Storage
###############################################################################
echo "==> Task 10/15: Installing Longhorn..."
helm repo add longhorn https://charts.longhorn.io
helm repo update
kubectl create ns longhorn-system || true

helm upgrade --install longhorn longhorn/longhorn -n longhorn-system \
  --set defaultSettings.defaultReplicaCount=2 \
  --set defaultSettings.nodeSelector="longhorn=storage"

# NEW: Wait for the StorageClass to appear before patching
echo "Waiting for Longhorn StorageClass to be created..."
until kubectl get storageclass longhorn >/dev/null 2>&1; do
  echo "Still waiting for storage class... (checking in 5s)"
  sleep 5
done

kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

###############################################################################
# 11. AWX Operator
###############################################################################
echo "==> Task 11/15: Deploying AWX Operator..."
[ ! -d "awx-operator" ] && git clone https://github.com/ansible/awx-operator.git
cd awx-operator && git checkout tags/${AWX_OPERATOR_VERSION}
kubectl apply -k config/default -n awx
kubectl -n awx rollout status deployment awx-operator-controller-manager --timeout=300s

###############################################################################
# 12. AWX Secrets & TLS
###############################################################################
echo "==> Task 12/15: Setting up AWX secrets..."
kubectl create ns ${AWX_NAMESPACE} || true
kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password --from-literal=password='Root@123' --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: awx-tls
  namespace: ${AWX_NAMESPACE}
spec:
  secretName: awx-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames: [ "${AWX_HOSTNAME}" ]
EOF

###############################################################################
# 13. AWX Custom Resource (High Performance Specs)
###############################################################################
echo "==> Task 13/15: Deploying AWX Instance..."
cat <<EOF | kubectl apply -n ${AWX_NAMESPACE} -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: ClusterIP
  ingress_type: ingress
  hostname: ${AWX_HOSTNAME}
  admin_password_secret: awx-admin-password

  # Postgres - Using the 4CPU/6GB stable configuration
  postgres_storage_class: longhorn
  postgres_resource_requirements:
    requests:
      cpu: "4"
      memory: "6Gi"
    limits:
      cpu: "4"
      memory: "6Gi"

  # Projects (RWX)
  projects_persistence: true
  projects_storage_class: longhorn
  projects_storage_access_mode: ReadWriteMany
  projects_storage_size: "8Gi"
EOF

###############################################################################
# 14. Performance & Permission Fixes
###############################################################################
echo "==> Task 14/15: Applying post-launch optimizations..."
kubectl -n awx set env deployment/awx-operator-controller-manager WATCH_AWXMESHINGRESS=false

# Kickstart permissions for the Postgres PVC
echo "Waiting for PVC to exist..."
sleep 10
kubectl -n awx run fix-pvc --rm -i --restart=Never --image=busybox \
  --overrides='{"spec":{"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"postgres-15-awx-prod-postgres-15-0"}}],"containers":[{"name":"f","image":"busybox","command":["chown","-R","26:26","/data"],"volumeMounts":[{"name":"v","mountPath":"/data"}]}]}}' || true

###############################################################################
# 15. Migration Watcher
###############################################################################
echo "==> Task 15/15: Watching for Migration Job..."
echo "This usually takes 2-3 minutes for the operator to reach this step."

until kubectl get job ${AWX_NAME}-migration -n ${AWX_NAMESPACE} >/dev/null 2>&1; do
  echo "Operator is reconciling... checking again in 20s"
  sleep 20
done



echo "✅ Migration Job found! Streaming logs now:"
kubectl logs -f job/${AWX_NAME}-migration -n ${AWX_NAMESPACE}
