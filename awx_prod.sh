#!/bin/bash
set -euo pipefail

###############################################################################
# AWX Production Setup - FINAL MASTER VERSION (RESILIENT NETWORKING)
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

echo "=== TASK 0: CLUSTER-WIDE NETWORK RESET & KERNEL TUNING ==="
dnf install -y sshpass git &>/dev/null

for IP in "$CONTROL_NODE_IP" "${WORKER_NODE_IPS[@]}"; do
    echo "Processing Node $IP..."
    sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${IP} "
        # 1. Stop services to unlock network interfaces
        systemctl stop kubelet containerd || true
        
        # 2. Deep clean CNI
        ip link delete cni0 || true
        ip link delete flannel.1 || true
        rm -rf /var/lib/cni/*
        rm -rf /etc/cni/net.d/*
        
        # 3. Kernel Tuning
        modprobe br_netfilter overlay
        cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.rp_filter         = 0
net.ipv4.conf.default.rp_filter     = 0
EOF
        sysctl --system &>/dev/null

        # 4. Longhorn Dependencies
        yum install -y iscsi-initiator-utils nfs-utils &>/dev/null
        systemctl enable --now iscsid

        # 5. Restart services
        systemctl start containerd
        systemctl start kubelet
    "
done

echo "Waiting for nodes to report Ready..."
sleep 20

# 1. Cleanup
echo "==> Task 1/16: Cleaning up..."
kubectl delete awx --all -n $AWX_NAMESPACE --ignore-not-found || true

# 2. Labeling Nodes
echo "==> Task 2/16: Labeling nodes..."
for NODE in "${WORKERS[@]}"; do
    kubectl label nodes $NODE nodepool=workloads longhorn=storage --overwrite || true
done

# 4. Networking (Flannel)
echo "==> Task 4/16: Deploying Flannel CNI..."
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
# Force restart Flannel to pick up the clean state
kubectl delete pods -n kube-flannel --all

# 5. Ingress
echo "==> Task 5/16: Installing NGINX Ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml

# 6. MetalLB
echo "==> Task 6/16: Deploying MetalLB Stack..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
sleep 30
kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found || true

# 7. IP Pool
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
spec:
  ipAddressPools:
  - awx-static-pool
EOF

# 8. Cert-Manager (Force restart to prevent CrashLoop)
echo "==> Task 8/16: Deploying Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
sleep 10
kubectl delete pods -n cert-manager --all

# 9. Longhorn Storage & SC Wait Fix
echo "==> Task 9/16: Deploying Longhorn..."
if ! command -v helm &> /dev/null; then
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh
fi

helm repo add longhorn https://charts.longhorn.io || true
helm repo update &>/dev/null
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace --set defaultSettings.defaultReplicaCount=1

echo "Nudging Longhorn components..."
# This solves the Init:0/1 hang
sleep 20
kubectl delete pods -n longhorn-system -l app=longhorn-manager || true
kubectl delete pods -n longhorn-system -l app=longhorn-driver-deployer || true

echo "Waiting for Longhorn StorageClass to be created..."
until kubectl get storageclass longhorn >/dev/null 2>&1; do
  echo "Still waiting for storageclass/longhorn..."
  sleep 10
done

kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 10. AWX Operator
echo "==> Task 10/16: Installing AWX Operator..."
kubectl create ns ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
[ -d "awx-operator" ] && rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git &>/dev/null
cd awx-operator && git checkout ${AWX_OPERATOR_VERSION} &>/dev/null
kubectl apply -k config/default -n ${AWX_NAMESPACE}
echo "Waiting for Operator to be ready..."
kubectl -n ${AWX_NAMESPACE} rollout status deployment awx-operator-controller-manager --timeout=300s
cd ..

# 11. Secrets
kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password --from-literal=password='Root@123' --dry-run=client -o yaml | kubectl apply -f -

# 12. AWX Instance
echo "==> Task 12/16: Deploying AWX Instance..."
cat <<EOF | kubectl apply -n awx -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: LoadBalancer
  loadbalancer_ip: 192.168.253.225
  ingress_type: ingress
  hostname: ${AWX_HOSTNAME}
  admin_password_secret: awx-admin-password
  postgres_storage_class: longhorn
  postgres_data_volume_init: true
EOF

# 14. Migration Watch
echo "==> Task 14/16: Database Migration starting..."
echo "This step can take 5-10 minutes. Monitoring..."
until kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" 2>/dev/null | grep -q "migration"; do 
    echo "Waiting for migration pod to appear..."
    sleep 15
done

MIGRATION_POD=$(kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f "$MIGRATION_POD" -n ${AWX_NAMESPACE} --tail=100 || true

# 16. Expose Longhorn
kubectl patch svc longhorn-frontend -n longhorn-system -p '{"spec": {"type": "LoadBalancer"}}'

echo "===================================================="
echo "DEPLOYMENT FINISHED"
echo "AWX: http://192.168.253.225"
echo "Longhorn UI: $(kubectl get svc longhorn-frontend -n longhorn-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "===================================================="
