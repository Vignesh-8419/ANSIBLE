#!/bin/bash
set -euo pipefail

AWX_NAMESPACE="awx"
AWX_NAME="awx-prod"
AWX_OPERATOR_VERSION="2.19.1"
AWX_HOSTNAME="awx-server-01.vgs.com"

CONTROL_NODE_IP="192.168.253.135"
WORKER_NODE_IPS=("192.168.253.136" "192.168.253.137")
WORKERS=("awx-work-node-01.vgs.com" "awx-work-node-02.vgs.com")
SSH_PASS="Root@123"

METALLB_POOL_START="192.168.253.220"
METALLB_POOL_END="192.168.253.230"

echo "==> Task 0: Dependencies & Helm..."
dnf install -y sshpass git openssl &>/dev/null
if ! command -v helm &> /dev/null; then
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh
fi

echo "==> Task 1: Node Prep & ISCSI (Required for Longhorn)..."
for IP in "$CONTROL_NODE_IP" "${WORKER_NODE_IPS[@]}"; do
    sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${IP} "
        yum install -y iscsi-initiator-utils nfs-utils &>/dev/null
        systemctl enable --now iscsid
        modprobe br_netfilter overlay || true
        sysctl -w net.ipv4.ip_forward=1 || true
    "
done

echo "==> Task 2: Label Nodes..."
for NODE in "${WORKERS[@]}"; do
    kubectl label nodes $NODE nodepool=workloads longhorn=storage --overwrite &>/dev/null
done

echo "==> Task 4: Flannel CNI..."
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "==> Task 5: NGINX Ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
# CRITICAL: Remove blocking webhook
kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found || true

echo "==> Task 6: MetalLB Deployment & Secret Fix..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
# FIX: Create the memberlist secret if it doesn't exist
if ! kubectl get secret memberlist -n metallb-system &>/dev/null; then
    kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
fi
# CRITICAL: Remove blocking webhook
kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found || true

echo "==> Task 7: MetalLB IP Pool..."
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

echo "==> Task 8: Cert-Manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

echo "==> Task 9: Longhorn Storage..."
helm repo add longhorn https://charts.longhorn.io || true
helm repo update &>/dev/null
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace --set defaultSettings.defaultReplicaCount=1
until kubectl get storageclass longhorn &>/dev/null; do sleep 10; done
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "==> Task 10: AWX Operator..."
kubectl create ns ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
[ -d "awx-operator" ] && rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git &>/dev/null
cd awx-operator && git checkout ${AWX_OPERATOR_VERSION} &>/dev/null
kubectl apply -k config/default -n ${AWX_NAMESPACE}
kubectl -n ${AWX_NAMESPACE} rollout status deployment awx-operator-controller-manager --timeout=300s
cd ..

echo "==> Task 11: AWX Admin Password..."
kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password --from-literal=password='Root@123' --dry-run=client -o yaml | kubectl apply -f -

echo "==> Task 12: AWX Instance..."
cat <<EOF | kubectl apply -n ${AWX_NAMESPACE} -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: LoadBalancer
  loadbalancer_ip: 192.168.253.225
  hostname: ${AWX_HOSTNAME}
  admin_password_secret: awx-admin-password
  postgres_storage_class: longhorn
EOF

echo "==> Tasks 13-16: Monitoring & Exposure..."
kubectl patch svc longhorn-frontend -n longhorn-system -p '{"spec": {"type": "LoadBalancer"}}' || true
echo "Setup complete. Waiting for pods to stabilize..."
kubectl get pods -A
