#!/bin/bash
set -euo pipefail

###############################################################################
# AWX Production Setup - FULL 16-STEP IDEMPOTENT MASTER SCRIPT
###############################################################################

AWX_NAMESPACE="awx"
AWX_NAME="awx-prod"
AWX_OPERATOR_VERSION="2.19.1"
AWX_HOSTNAME="awx-server-01.vgs.com"

# Nodes
CONTROL_NODE_IP="192.168.253.135"
WORKER_NODE_IPS=("192.168.253.136" "192.168.253.137")
WORKERS=("awx-work-node-01.vgs.com" "awx-work-node-02.vgs.com")
SSH_PASS="Root@123"

# MetalLB Config
METALLB_POOL_START="192.168.253.220"
METALLB_POOL_END="192.168.253.230"

echo "==> Task 0: Installing local dependencies (sshpass, git, helm)..."
dnf install -y sshpass git &>/dev/null
if ! command -v helm &> /dev/null; then
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh
fi

echo "==> Task 1: Node Kernel & Network Prep..."
for IP in "$CONTROL_NODE_IP" "${WORKER_NODE_IPS[@]}"; do
    if ! sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${IP} "ip addr show flannel.1" &>/dev/null; then
        echo "Resetting Network/Kernel on $IP..."
        sshpass -p "${SSH_PASS}" ssh root@${IP} "
            modprobe br_netfilter overlay vxlan || true
            sysctl -w net.ipv4.ip_forward=1 || true
            yum install -y iscsi-initiator-utils nfs-utils &>/dev/null
            systemctl enable --now iscsid &>/dev/null
            systemctl restart containerd kubelet
        "
    else
        echo "Node $IP is healthy. Skipping reset."
    fi
done

echo "==> Task 2: Labeling nodes for Storage..."
for NODE in "${WORKERS[@]}"; do
    kubectl label nodes $NODE nodepool=workloads longhorn=storage --overwrite &>/dev/null
done

echo "==> Task 3: Verifying Cluster Nodes..."
kubectl get nodes

echo "==> Task 4: Deploying Flannel CNI..."
if ! kubectl get ds kube-flannel-ds -n kube-flannel &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
fi

echo "==> Task 5: Installing NGINX Ingress..."
if ! kubectl get ns ingress-nginx &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
fi

echo "==> Task 6: Deploying MetalLB Stack..."
if ! kubectl get ns metallb-system &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
    echo "Waiting for MetalLB..."
    sleep 30
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found || true
fi

echo "==> Task 7: Configuring MetalLB IP Pools..."
if ! kubectl get ipaddresspool awx-static-pool -n metallb-system &>/dev/null; then
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
fi

echo "==> Task 8: Deploying Cert-Manager..."
if ! kubectl get ns cert-manager &>/dev/null; then
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
fi

echo "==> Task 9: Deploying Longhorn Storage..."
if ! kubectl get storageclass longhorn &>/dev/null; then
    helm repo add longhorn https://charts.longhorn.io || true
    helm repo update &>/dev/null
    helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace --set defaultSettings.defaultReplicaCount=1
    echo "Waiting for Longhorn StorageClass..."
    until kubectl get storageclass longhorn &>/dev/null; do sleep 10; done
    kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
fi

echo "==> Task 10: Installing AWX Operator..."
if ! kubectl get deployment awx-operator-controller-manager -n ${AWX_NAMESPACE} &>/dev/null; then
    kubectl create ns ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    [ -d "awx-operator" ] && rm -rf awx-operator
    git clone https://github.com/ansible/awx-operator.git &>/dev/null
    cd awx-operator && git checkout ${AWX_OPERATOR_VERSION} &>/dev/null
    kubectl apply -k config/default -n ${AWX_NAMESPACE}
    kubectl -n ${AWX_NAMESPACE} rollout status deployment awx-operator-controller-manager --timeout=300s
    cd ..
fi

echo "==> Task 11: Creating AWX Admin Secrets..."
if ! kubectl get secret awx-admin-password -n ${AWX_NAMESPACE} &>/dev/null; then
    kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password --from-literal=password='Root@123'
fi

echo "==> Task 12: Deploying AWX Instance..."
if ! kubectl get awx ${AWX_NAME} -n ${AWX_NAMESPACE} &>/dev/null; then
    cat <<EOF | kubectl apply -n ${AWX_NAMESPACE} -f -
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
fi

echo "==> Task 13: Waiting for Postgres/Web Pods..."
sleep 20
kubectl get pods -n ${AWX_NAMESPACE}

echo "==> Task 14: Monitoring Database Migration..."
# Check if migration pod exists and is running
if kubectl get pods -n ${AWX_NAMESPACE} | grep -q "migration"; then
    MIGRATION_POD=$(kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$MIGRATION_POD" ]; then
        kubectl logs -f "$MIGRATION_POD" -n ${AWX_NAMESPACE} --tail=50 || true
    fi
fi

echo "==> Task 15: Final Service Exposure..."
kubectl patch svc longhorn-frontend -n longhorn-system -p '{"spec": {"type": "LoadBalancer"}}' &>/dev/null || true

echo "==> Task 16: Verification & Summary..."
echo "----------------------------------------------------"
echo "AWX Status:"
kubectl get awx -n ${AWX_NAMESPACE}
echo "----------------------------------------------------"
echo "Access URL: http://192.168.253.225"
echo "Login: admin / Root@123"
echo "----------------------------------------------------"
