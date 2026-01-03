#!/bin/bash

# --- 1. Environment Setup ---
set -e
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
VIP="192.168.253.225"
ADMIN_PASSWORD="Root@123"

echo "📦 Installing prerequisites..."
dnf install -y git make curl gettext net-tools
systemctl stop firewalld
systemctl disable firewalld

# --- 2. Virtual IP Assignment ---
echo "🌐 Assigning Virtual IP $VIP to loopback..."
# Adding to lo (loopback) allows the OS to accept traffic for this IP
ip addr add $VIP/32 dev lo || echo "VIP already assigned to lo"

# --- 3. K3s Installation ---
echo "☸️ Installing K3s (Kubernetes)..."
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
    mkdir -p $HOME/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
    sudo chmod 600 $HOME/.kube/config
fi

# --- 4. Install Kustomize (Required for AWX Operator) ---
if ! command -v kustomize &> /dev/null; then
    echo "🛠️ Installing Kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
fi

# --- 5. Critical Fix: Metrics Server Patch ---
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

# --- 6. AWX Operator Deployment ---
echo "🏗️ Deploying AWX Operator (v$OPERATOR_VERSION)..."
if [ ! -d "awx-operator" ]; then
    git clone https://github.com/ansible/awx-operator.git
fi

cd awx-operator
git checkout $OPERATOR_VERSION

# Create namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Pre-create the admin password secret
echo "🔑 Setting Admin Password to $ADMIN_PASSWORD..."
kubectl create secret generic awx-server-admin-password \
  --from-literal=password=$ADMIN_PASSWORD \
  -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy the operator
make deploy NAMESPACE=$NAMESPACE

# --- 7. AWX Instance Creation ---
echo "🚀 Creating AWX Instance on $VIP..."
# NOTE: Fields must be CamelCase (externalIPs, serviceType)
cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
spec:
  service_type: LoadBalancer
  externalIPs:
    - $VIP
  admin_password_secret: awx-server-admin-password
  postgres_storage_class: local-path
EOF

kubectl apply -f awx-instance.yaml -n $NAMESPACE

# --- 8. Final Summary ---
echo "-------------------------------------------------------"
echo "✅ AWX Installation Started!"
echo "-------------------------------------------------------"
echo "🌐 URL: http://$VIP"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "-------------------------------------------------------"
echo "🔍 Monitor progress with the command below:"
echo "kubectl get pods -n $NAMESPACE -w"
