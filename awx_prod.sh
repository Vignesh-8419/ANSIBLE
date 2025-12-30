#!/bin/bash
set -euo pipefail

###############################################################################
# AWX Production Setup - IDEMPOTENT & RESILIENT VERSION
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

echo "=== TASK 0: NODE PREP (SKIPS IF ALREADY CONFIGURED) ==="
dnf install -y sshpass git &>/dev/null

for IP in "$CONTROL_NODE_IP" "${WORKER_NODE_IPS[@]}"; do
    echo "Checking Node $IP..."
    # Skip reset if flannel interface already exists on the node
    if ! sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@${IP} "ip addr show flannel.1" &>/dev/null; then
        echo "Configuring network and dependencies on $IP..."
        sshpass -p "${SSH_PASS}" ssh root@${IP} "
            modprobe br_netfilter overlay vxlan || true
            sysctl -w net.ipv4.ip_forward=1 || true
            yum install -y iscsi-initiator-utils nfs-utils &>/dev/null
            systemctl enable --now iscsid &>/dev/null
            systemctl restart containerd kubelet
        "
    else
        echo "Node $IP network already active. Skipping reset."
    fi
done

# 2. Labeling Nodes
echo "==> Task 2/16: Labeling nodes..."
for NODE in "${WORKERS[@]}"; do
    kubectl label nodes $NODE nodepool=workloads longhorn=storage --overwrite &>/dev/null
done

# 4. Networking (Flannel)
echo "==> Task 4/16: Checking Flannel..."
if ! kubectl get daemonset kube-flannel-ds -n kube-flannel &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
else
    echo "Flannel already deployed."
fi

# 5. Ingress
echo "==> Task 5/16: Checking NGINX Ingress..."
if ! kubectl get ns ingress-nginx &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
else
    echo "NGINX Ingress already deployed."
fi

# 6. MetalLB
echo "==> Task 6/16: Checking MetalLB..."
if ! kubectl get ns metallb-system &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
    sleep 20
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found || true
    
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
else
    echo "MetalLB already configured."
fi

# 8. Cert-Manager
echo "==> Task 8/16: Checking Cert-Manager..."
if ! kubectl get ns cert-manager &>/dev/null; then
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
else
    echo "Cert-Manager already deployed."
fi

# 9. Longhorn
echo "==> Task 9/16: Checking Longhorn..."
if ! kubectl get storageclass longhorn &>/dev/null; then
    helm repo add longhorn https://charts.longhorn.io || true
    helm repo update &>/dev/null
    helm upgrade --install longhorn longhorn/longhorn -n longhorn-system --create-namespace --set defaultSettings.defaultReplicaCount=1
    
    echo "Waiting for StorageClass..."
    until kubectl get storageclass longhorn &>/dev/null; do sleep 5; done
    kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
else
    echo "Longhorn StorageClass ready."
fi

# 10. AWX Operator
echo "==> Task 10/16: Checking AWX Operator..."
if ! kubectl get deployment awx-operator-controller-manager -n ${AWX_NAMESPACE} &>/dev/null; then
    kubectl create ns ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    [ -d "awx-operator" ] && rm -rf awx-operator
    git clone https://github.com/ansible/awx-operator.git &>/dev/null
    cd awx-operator && git checkout ${AWX_OPERATOR_VERSION} &>/dev/null
    kubectl apply -k config/default -n ${AWX_NAMESPACE}
    kubectl -n ${AWX_NAMESPACE} rollout status deployment awx-operator-controller-manager --timeout=300s
    cd ..
else
    echo "AWX Operator already running."
fi

# 12. AWX Instance
echo "==> Task 12/16: Checking AWX Instance..."
if ! kubectl get awx ${AWX_NAME} -n ${AWX_NAMESPACE} &>/dev/null; then
    kubectl -n ${AWX_NAMESPACE} create secret generic awx-admin-password --from-literal=password='Root@123' --dry-run=client -o yaml | kubectl apply -f -
    
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
EOF
else
    echo "AWX Instance already exists."
fi

# 14. Migration Watch (Only if pod exists and is not completed)
echo "==> Task 14/16: Monitoring Migration..."
if kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" | grep -q "Running"; then
    MIGRATION_POD=$(kubectl get pods -n ${AWX_NAMESPACE} -l "app.kubernetes.io/component=migration" -o jsonpath='{.items[0].metadata.name}')
    kubectl logs -f "$MIGRATION_POD" -n ${AWX_NAMESPACE} --tail=100 || true
else
    echo "Migration pod not currently running or already finished."
fi

# 16. Expose Longhorn
kubectl patch svc longhorn-frontend -n longhorn-system -p '{"spec": {"type": "LoadBalancer"}}' &>/dev/null || true

echo "===================================================="
echo "STATUS SUMMARY"
kubectl get nodes
kubectl get pods -n ${AWX_NAMESPACE}
echo "AWX Access: http://192.168.253.225"
echo "===================================================="
