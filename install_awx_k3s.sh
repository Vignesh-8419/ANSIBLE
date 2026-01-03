#!/bin/bash

# --- 1. Environment Setup ---
set -e
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
VIP="192.168.253.225"

echo "📦 Installing prerequisites..."
dnf install -y git make curl gettext
systemctl stop firewalld
systemctl disable firewalld

# --- 2. K3s Installation ---
echo "☸️ Installing K3s (Kubernetes)..."
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
    mkdir -p $HOME/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
    sudo chmod 600 $HOME/.kube/config
fi

# --- 3. Critical Fix: Metrics Server Patch ---
echo "⏳ Waiting for Metrics Server to initialize..."
MAX_RETRIES=30
COUNT=0
while ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; do
    sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then echo "❌ Metrics server timeout"; exit 1; fi
done

echo "🔧 Patching Metrics Server for API discovery..."
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# --- 4. Kustomize Installation ---
echo "🛠️ Installing Kustomize..."
if ! command -v kustomize &> /dev/null; then
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
fi

# --- 5. AWX Operator Deployment ---
echo "🏗️ Deploying AWX Operator (v$OPERATOR_VERSION)..."
if [ ! -d "awx-operator" ]; then
    git clone https://github.com/ansible/awx-operator.git
fi

cd awx-operator
git checkout $OPERATOR_VERSION

# Create namespace and deploy
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
make deploy NAMESPACE=$NAMESPACE

# --- 6. AWX Instance Creation (Final VIP Logic) ---
echo "🚀 Creating AWX Instance..."
# Ensure the VIP is active on the host
ip addr add 192.168.253.225/32 dev lo || true

cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
spec:
  service_type: loadbalancer
  external_ips:
    - 192.168.253.225
    - 192.168.253.145
  postgres_storage_class: local-path
EOF

kubectl apply -f awx-instance.yaml -n $NAMESPACE

# --- 7. Final Instructions ---
echo "-------------------------------------------------------"
echo "✅ Installation commands completed successfully!"
echo "-------------------------------------------------------"
echo "🌐 AWX URL: http://$VIP"
echo "🔑 Admin Password Command:"
echo "   kubectl get secret awx-server-admin-password -n $NAMESPACE -o jsonpath='{.data.password}' | base64 --decode; echo"
echo "-------------------------------------------------------"
