#!/bin/bash

# --- 1. Environment Setup ---
set -e
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
VIP="192.168.253.145"
ADMIN_PASSWORD="Root@123"
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

echo "📦 Installing prerequisites..."
dnf install -y git make curl gettext net-tools
systemctl stop firewalld || true
systemctl disable firewalld || true

# --- 2. Virtual IP Assignment ---
echo "🌐 Assigning Virtual IP $VIP to $INTERFACE..."
ip addr del $VIP/32 dev lo 2>/dev/null || true
if ! ip addr show $INTERFACE | grep -q "$VIP"; then
    ip addr add $VIP/24 dev $INTERFACE
fi

# --- 3. K3s Installation & Path Fixes ---
echo "☸️ Installing K3s (Kubernetes)..."
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
fi

# IMPORTANT: Link kubectl and export paths immediately
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
export PATH=$PATH:/usr/local/bin
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "⏳ Waiting for k3s.yaml to be generated..."
until [ -f /etc/rancher/k3s/k3s.yaml ]; do sleep 2; done

mkdir -p $HOME/.kube
cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
chmod 600 $HOME/.kube/config

# --- 4. Install Kustomize ---
if ! command -v kustomize &> /dev/null; then
    echo "🛠️ Installing Kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    mv kustomize /usr/local/bin/
fi

# --- 5. Metrics Server Patch ---
echo "⏳ Waiting for K3s Node and Metrics Server..."
until kubectl get nodes | grep -q "Ready"; do sleep 5; done
until kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; do sleep 5; done

kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# --- 6. AWX Operator Deployment ---
echo "🏗️ Deploying AWX Operator..."
# Clean up old clone if it exists to avoid git checkout errors
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
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

# --- 8. Ingress Configuration ---
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

# --- 9. The Wait Loop ---
echo "⏳ Waiting for AWX UI to be ready at http://$VIP..."
echo "This takes 5-10 mins. Migrations are running in the background."

# Loop until we get a 200 OK from the web service
# Note: Added -m 5 to curl to avoid hanging on slow responses
until [ "$(curl -s -L -o /dev/null -w "%{http_code}" http://$VIP --connect-timeout 5)" == "200" ]; do
    printf "."
    sleep 10
done

echo -e "\n-------------------------------------------------------"
echo "✅ AWX IS READY!"
echo "🌐 URL: http://$VIP"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "-------------------------------------------------------"
