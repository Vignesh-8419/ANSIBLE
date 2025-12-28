#!/bin/bash
set -euo pipefail

################################################################################
# Kubernetes + AWX Production Migration Script
# For migrating from lab to production
# Features:
# - Applies br_netfilter + sysctl fixes on all nodes
# - Cleans old CNI state
# - Installs Flannel + waits for readiness
# - Installs Local-Path & Longhorn storage
# - Deploys AWX Operator and AWX Instance
# - Requires passwordless SSH to worker nodes
################################################################################

CONTROL_PLANE_NODE="awx-control-node-01"
WORKER_NODES=("awx-work-node-01" "awx-work-node-02")  # Update accordingly
AWX_NAMESPACE="awx"
AWX_NAME="awx-demo"
AWX_OPERATOR_VERSION="2.7.2"
ADMIN_PASSWORD="ProdSecretPassword123"
DNS_SERVER="192.168.253.151"
POD_NETWORK_CIDR="10.244.0.0/16"

################################################################################
# 0️⃣ Kernel & Networking Fixes (All Nodes)
################################################################################
echo "=== Applying kernel and networking fixes on all nodes ==="
ALL_NODES=("$CONTROL_PLANE_NODE" "${WORKER_NODES[@]}")
for NODE in "${ALL_NODES[@]}"; do
    echo "Applying fixes on ${NODE}..."
    ssh root@"${NODE}" bash -c "'
modprobe br_netfilter
echo br_netfilter > /etc/modules-load.d/br_netfilter.conf
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.bridge.bridge-nf-call-ip6tables=1
sysctl -w net.ipv4.ip_forward=1
cat <<EOF >> /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
'"
done

################################################################################
# 1️⃣ Stop kubelet & clean old CNI (Control Plane)
################################################################################
echo "=== Cleaning old CNI on control-plane node ==="
systemctl stop kubelet || true
ip link delete cni0 || true
ip link delete flannel.1 || true
rm -rf /var/lib/cni/networks/* /var/lib/cni/bin/* /etc/cni/net.d/*
systemctl start kubelet

################################################################################
# 2️⃣ Stop firewall and SELinux (All Nodes)
################################################################################
echo "=== Disabling firewall and SELinux on all nodes ==="
for NODE in "${ALL_NODES[@]}"; do
    ssh root@"${NODE}" bash -c "'
systemctl stop firewalld || true
systemctl disable firewalld || true
iptables -F || true
setenforce 0 || true
'"
done

################################################################################
# 3️⃣ Initialize Kubernetes (Control Plane)
################################################################################
echo "=== Initializing Kubernetes on control-plane ==="
kubeadm init --pod-network-cidr=${POD_NETWORK_CIDR} --upload-certs

export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Save join commands for workers
kubeadm token create --print-join-command > /root/kubeadm-join-cmd.sh
chmod +x /root/kubeadm-join-cmd.sh

################################################################################
# 4️⃣ Join Worker Nodes
################################################################################
echo "=== Joining worker nodes ==="
for NODE in "${WORKER_NODES[@]}"; do
    echo "Joining ${NODE}..."
    ssh root@"${NODE}" 'bash -s' < /root/kubeadm-join-cmd.sh
done

################################################################################
# 5️⃣ Install Flannel CNI
################################################################################
echo "=== Installing Flannel CNI ==="
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "Waiting for Flannel pods to be Ready..."
for i in {1..30}; do
    NOT_READY=$(kubectl get pods -n kube-flannel -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep false || true)
    if [[ -z "$NOT_READY" ]]; then
        echo "Flannel pods are Ready"
        break
    fi
    echo "Waiting for Flannel... (${i}/30)"
    sleep 10
done

kubectl get pods -n kube-flannel -o wide

################################################################################
# 6️⃣ Install Local Path Provisioner
################################################################################
echo "=== Installing Local-Path Provisioner ==="
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass

################################################################################
# 7️⃣ Install Longhorn (Production PVs)
################################################################################
echo "=== Installing Longhorn ==="
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
kubectl get pods -n longhorn-system -w

################################################################################
# 8️⃣ Deploy AWX Operator
################################################################################
echo "=== Deploying AWX Operator ==="
kubectl create namespace ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml
kubectl get pods -n ${AWX_NAMESPACE} -o wide

################################################################################
# 9️⃣ Deploy AWX Instance
################################################################################
kubectl create secret generic awx-admin-password \
  --from-literal=password="${ADMIN_PASSWORD}" \
  -n ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
  namespace: ${AWX_NAMESPACE}
spec:
  service_type: NodePort
EOF

kubectl get pods -n ${AWX_NAMESPACE} -o wide
kubectl get svc -n ${AWX_NAMESPACE}

################################################################################
# 🔹 Post-Deployment Tests
################################################################################
echo "=== Testing CoreDNS and AWX connectivity ==="
kubectl run -it --rm busybox \
  --image=busybox --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local

kubectl run -it --rm busybox \
  --image=busybox --restart=Never -- \
  ping -c 3 10.96.0.1

echo "=== Migration to production completed successfully ==="
