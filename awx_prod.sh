#!/bin/bash
# ==============================================================================
# AWX PRODUCTION DEPLOYMENT - FULL 16-STEP MASTER SCRIPT
# ==============================================================================
# Target: RHEL/CentOS/Rocky Linux 8/9
# Includes: Flannel, MetalLB, Cert-Manager, Longhorn, NGINX Ingress, AWX Operator
# ==============================================================================

set -e

# --- 1. CONFIGURATION VARIABLES ---
AWX_NAMESPACE="awx"
AWX_NAME="awx-prod"
AWX_OPERATOR_VERSION="2.19.1"
AWX_HOSTNAME="awx-server-01.vgs.com"
CONTROL_NODE="awx-control-node-01.vgs.com"
WORKERS=("awx-work-node-01.vgs.com" "awx-work-node-02.vgs.com")
WORKER_IPS=("192.168.253.136" "192.168.253.137")
SSH_PASS="Root@123"
METALLB_START="192.168.253.220"
METALLB_END="192.168.253.230"
AWX_LB_IP="192.168.253.225"

echo "Starting AWX Infrastructure Deployment..."

# --- 2. TASK 1: SYSTEM DEPENDENCIES ---
echo "==> Task 1/16: Installing local control tools..."
dnf install -y sshpass git openssl curl &>/dev/null
echo "Done."

# --- 3. TASK 2: HELM INSTALLATION ---
echo "==> Task 2/16: Checking/Installing Helm..."
if ! command -v helm &> /dev/null; then
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
fi
helm version --short
echo "Done."

# --- 4. TASK 3: NODE PREPARATION (REMOTE) ---
echo "==> Task 3/16: Preparing Remote Worker Nodes (ISCSI/Kernel)..."
for IP in "${WORKER_IPS[@]}"; do
    echo "Configuring $IP..."
    sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${IP} "
        # Install storage requirements for Longhorn
        yum install -y iscsi-initiator-utils nfs-utils &>/dev/null
        systemctl enable --now iscsid
        # Enable kernel modules
        modprobe br_netfilter overlay || true
        # Enable IP Forwarding
        echo '1' > /proc/sys/net/ipv4/ip_forward
        # Refresh Kubelet
        systemctl restart containerd kubelet
    "
done

# --- 5. TASK 4: NODE LABELING ---
echo "==> Task 4/16: Labeling Workers for Workloads and Storage..."
for NODE in "${WORKERS[@]}"; do
    kubectl label nodes $NODE nodepool=workloads --overwrite || true
    kubectl label nodes $NODE longhorn=storage --overwrite || true
done

# --- 6. TASK 5: NETWORK CNI (FLANNEL) ---
echo "==> Task 5/16: Deploying Flannel CNI..."
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
echo "Waiting for Flannel pods..."
kubectl rollout status ds kube-flannel-ds -n kube-flannel --timeout=120s

# --- 7. TASK 6: NGINX INGRESS CONTROLLER ---
echo "==> Task 6/16: Deploying NGINX Ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
# Critical Fix: Remove the admission webhook that blocks pod scheduling
echo "Unblocking Ingress Admission Webhook..."
kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found || true

# --- 8. TASK 7: METALLB DEPLOYMENT ---
echo "==> Task 7/16: Deploying MetalLB LoadBalancer..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# --- 9. TASK 8: METALLB SECRET & WEBHOOK FIX ---
echo "==> Task 8/16: Configuring MetalLB Security & Webhooks..."
if ! kubectl get secret memberlist -n metallb-system &>/dev/null; then
    kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
fi
# Critical Fix: Remove the MetalLB webhook that causes Pending status
kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found || true

# --- 10. TASK 9: METALLB IP ADDRESS POOL ---
echo "==> Task 9/16: Applying L2 Advertisement and IP Pool..."
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: awx-static-pool
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_START}-${METALLB_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: awx-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - awx-static-pool
EOF

# --- 11. TASK 10: CERT-MANAGER ---
echo "==> Task 10/16: Deploying Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
echo "Waiting for Cert-Manager..."
sleep 20

# --- 12. TASK 11: LONGHORN STORAGE ---
echo "==> Task 11/16: Deploying Longhorn Storage..."
helm repo add longhorn https://charts.longhorn.io || true
helm repo update
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace \
  --set defaultSettings.defaultReplicaCount=1 \
  --set defaultSettings.storageOverProvisioningPercentage=200
  
echo "Waiting for Longhorn StorageClass..."
until kubectl get storageclass longhorn &>/dev/null; do 
    echo "...still waiting for longhorn storageclass..."
    sleep 10
done
# Set as default storage
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# --- 13. TASK 12: AWX OPERATOR INSTALLATION ---
echo "==> Task 12/16: Deploying AWX Operator..."
kubectl create ns ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
if [ -d "awx-operator" ]; then rm -rf awx-operator; fi
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git checkout ${AWX_OPERATOR_VERSION}
export NAMESPACE=${AWX_NAMESPACE}
make deploy
echo "Waiting for Operator pod to be ready..."
kubectl rollout status deployment awx-operator-controller-manager -n ${AWX_NAMESPACE} --timeout=300s
cd ..

# --- 14. TASK 13: AWX ADMIN SECRETS ---
echo "==> Task 13/16: Creating AWX Admin Password Secret..."
kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password \
    --from-literal=password='Root@123' \
    --dry-run=client -o yaml | kubectl apply -f -

# --- 15. TASK 14: AWX INSTANCE DEPLOYMENT ---
echo "==> Task 14/16: Deploying AWX Custom Resource (Instance)..."
cat <<EOF | kubectl apply -n ${AWX_NAMESPACE} -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: LoadBalancer
  loadbalancer_ip: ${AWX_LB_IP}
  ingress_type: ingress
  hostname: ${AWX_HOSTNAME}
  admin_password_secret: awx-admin-password
  postgres_storage_class: longhorn
  postgres_resource_requirements:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
EOF

# --- 16. TASK 15: STORAGE FRONTEND EXPOSURE ---
echo "==> Task 15/16: Exposing Longhorn Dashboard..."
kubectl patch svc longhorn-frontend -n longhorn-system -p '{"spec": {"type": "LoadBalancer"}}' || true

# --- 17. TASK 16: VERIFICATION & LOGS ---
echo "==> Task 16/16: Final Cluster Health Check..."
echo "--------------------------------------------------------"
kubectl get nodes
echo "--------------------------------------------------------"
kubectl get pods -A
echo "--------------------------------------------------------"
echo "Check AWX Status with: kubectl get awx -n ${AWX_NAMESPACE}"
echo "Deployment Finished."
