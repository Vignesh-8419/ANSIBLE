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
ip addr add $VIP/32 dev lo || echo "VIP already assigned to lo"

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
# We use NodePort here because the AWX CRD is strict about its allowed fields
cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
spec:
  service_type: nodeport
  nodeport_port: 31133
  admin_password_secret: awx-server-admin-password
  postgres_storage_class: local-path
EOF

kubectl apply -f awx-instance.yaml -n $NAMESPACE

# --- 8. VIP Forwarding (The "Secret Sauce") ---
# Since the AWX CRD doesn't support externalIPs directly, we create a side-service 
# that maps your VIP to the AWX pods on port 80.
echo "🔗 Mapping VIP $VIP to AWX..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: awx-vip-service
  namespace: $NAMESPACE
spec:
  type: LoadBalancer
  externalIPs:
    - $VIP
  ports:
    - port: 80
      targetPort: 8052
      protocol: TCP
  selector:
    app.kubernetes.io/component: web
    app.kubernetes.io/managed-by: awx-operator
    app.kubernetes.io/name: awx-server
EOF

echo "-------------------------------------------------------"
echo "✅ AWX Reinstall Initialized!"
echo "🌐 URL: http://$VIP (Port 80)"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "-------------------------------------------------------"
echo "🔍 Monitor with: kubectl get pods -n $NAMESPACE -w"
