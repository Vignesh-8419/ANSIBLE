#!/bin/bash

# --- Configuration Variables ---
ADMIN_PASS="Root@123"
AWX_IP="192.168.253.225"
AWX_HOSTNAME="awx-server-01.vgs.com"
WORKER1="192.168.253.136"
WORKER2="192.168.253.137"

echo "===================================================="
echo "Starting AWX Infrastructure Deployment"
echo "===================================================="

# 0. Install Helm (New Fix)
if ! command -v helm &> /dev/null; then
    echo "[0/7] Helm not found. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh
    rm -f get_helm.sh
else
    echo "[0/7] Helm is already installed."
fi

# 1. Prepare Nodes
echo "[1/7] Preparing Worker Nodes..."
prepare_node() {
  local IP=$1
  sshpass -p "${ADMIN_PASS}" ssh -o StrictHostKeyChecking=no root@${IP} "
    modprobe br_netfilter overlay
    echo -e 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\nnet.ipv4.conf.all.rp_filter = 0\nnet.ipv4.conf.default.rp_filter = 0' > /etc/sysctl.d/k8s.conf
    sysctl --system
    yum install -y iscsi-initiator-utils nfs-utils
    systemctl enable --now iscsid
  "
}
prepare_node $WORKER1
prepare_node $WORKER2

kubectl label nodes awx-work-node-01.vgs.com nodepool=workloads longhorn=storage --overwrite
kubectl label nodes awx-work-node-02.vgs.com nodepool=workloads longhorn=storage --overwrite

# 2. Networking (MetalLB & Ingress)
echo "[2/7] Installing Networking (Ingress & MetalLB)..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

echo "Waiting 60s for MetalLB pods to initialize..."
sleep 60
kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: awx-static-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.253.220-192.168.253.224
  - 192.168.253.226-192.168.253.230
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: awx-fixed-ip
  namespace: metallb-system
spec:
  addresses:
  - ${AWX_IP}/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: awx-combined-adv
  namespace: metallb-system
spec:
  ipAddressPools: [awx-static-pool, awx-fixed-ip]
EOF

# 3. Longhorn
echo "[3/7] Installing Longhorn Storage..."
helm repo add longhorn https://charts.longhorn.io && helm repo update
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace --set defaultSettings.defaultReplicaCount=1
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "--> Longhorn components are starting. This takes about 10 minutes. Waiting..."
sleep 600

# 4. AWX Operator
echo "[4/7] Deploying AWX Operator 2.19.1..."
kubectl create ns awx || true
# Navigate to home or a temp dir to clone
cd ~
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator && git checkout 2.19.1
kubectl apply -k config/default -n awx

echo "--> Operator is deploying. This takes about 7 minutes. Waiting..."
sleep 420

# 5. AWX Instance
echo "[5/7] Creating AWX Instance (awx-prod)..."
kubectl -n awx create secret generic awx-admin-password --from-literal=password="${ADMIN_PASS}" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -n awx -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-prod
spec:
  service_type: LoadBalancer
  service_annotations: "metallb.io/address-pool: awx-fixed-ip"
  loadbalancer_ip: ${AWX_IP}
  hostname: ${AWX_HOSTNAME}
  admin_password_secret: awx-admin-password
  postgres_storage_class: longhorn
  postgres_data_volume_init: true
  web_resource_requirements: { requests: { cpu: "500m", memory: "1Gi" } }
  task_resource_requirements: { requests: { cpu: "500m", memory: "1Gi" } }
EOF

# 6. Final Wait for Migration
echo "[6/7] AWX Instance Created. This takes 15+ minutes for migrations and pods. Waiting..."
sleep 900

# 7. Cleanup & Verify
echo "[7/7] Finalizing..."
kubectl delete pod -n awx -l control-plane=controller-manager

echo "===================================================="
echo "DEPLOYMENT COMPLETE"
echo "AWX URL: http://${AWX_HOSTNAME}"
echo "Admin User: admin"
echo "Admin Pass: ${ADMIN_PASS}"
echo "===================================================="
kubectl get pods -n awx
