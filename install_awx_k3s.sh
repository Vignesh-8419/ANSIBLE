#!/bin/bash

# --- 1. Environment Setup ---
set -e
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
VIP="192.168.253.225"
ADMIN_PASSWORD="Root@123"
# Automate finding the primary interface (usually ens192 or eth0)
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

echo "📦 Installing prerequisites..."
dnf install -y git make curl gettext net-tools
systemctl stop firewalld
systemctl disable firewalld

# --- 2. Virtual IP Assignment ---
echo "🌐 Assigning Virtual IP $VIP to $INTERFACE..."
# Removing from loopback if it exists there from previous runs
ip addr del $VIP/32 dev lo 2>/dev/null || true
# Adding to physical interface so it's reachable on the network
ip addr add $VIP/24 dev $INTERFACE 2>/dev/null || echo "VIP already assigned"

# --- 3. K3s Installation ---
echo "☸️ Installing K3s (Kubernetes)..."
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
    mkdir -p $HOME/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
    sudo chmod 600 $HOME/.kube/config
fi

# --- 4. Install Kustomize ---
if ! command -v kustomize &> /dev/null; then
    echo "🛠️ Installing Kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
fi

# --- 5. Metrics Server Patch ---
echo "⏳ Waiting for Metrics Server..."
until kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; do sleep 5; done
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# --- 6. AWX Operator Deployment ---
echo "🏗️ Deploying AWX Operator..."
if [ ! -d "awx-operator" ]; then
    git clone https://github.com/ansible/awx-operator.git
fi
cd awx-operator
git checkout $OPERATOR_VERSION

kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic awx-server-admin-password \
  --from-literal=password=$ADMIN_PASSWORD \
  -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

make deploy NAMESPACE=$NAMESPACE

# --- 7. AWX Instance Creation ---
echo "🚀 Creating AWX Instance..."
cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
spec:
  service_type: ClusterIP
  admin_password_secret: awx-server-admin-password
  postgres_storage_class: local-path
EOF

kubectl apply -f awx-instance.yaml -n $NAMESPACE

# --- 8. Ingress Configuration (The "Secret Sauce") ---
echo "🔗 Creating Ingress for VIP $VIP..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: awx-ingress
  namespace: $NAMESPACE
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: awx-server-service
            port:
              number: 80
EOF

echo "-------------------------------------------------------"
echo "✅ AWX Configuration Updated!"
echo "🌐 URL: http://$VIP"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "-------------------------------------------------------"
echo "🔍 Monitor with: kubectl get pods -n $NAMESPACE -w"
