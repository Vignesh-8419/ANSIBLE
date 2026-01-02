#!/bin/bash

# Exit on error
set -e

echo "📦 Installing prerequisites..."
dnf install -y git make curl gettext

# 1. Install K3s
echo "☸️ Installing K3s (Kubernetes)..."
curl -sfL https://get.k3s.io | sh -
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
export KUBECONFIG=~/.kube/config

# Wait for K3s to be ready
echo "⏳ Waiting for K3s to initialize..."
sleep 20

# 2. Install Kustomize
echo "🛠️ Installing Kustomize..."
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
chmod +x kustomize
sudo mv kustomize /usr/local/bin/

# 3. Deploy AWX Operator
echo "🏗️ Deploying AWX Operator (v2.19.1)..."
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git checkout 2.19.1

# Create namespace and deploy
export NAMESPACE=awx
kubectl create namespace $NAMESPACE || true
kubectl config set-context --current --namespace=$NAMESPACE
make deploy

echo "⏳ Waiting for Operator pod to start..."
sleep 60

# 4. Deploy AWX Instance
echo "🚀 Creating AWX Instance..."
cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
spec:
  service_type: nodeport
  postgres_storage_class: local-path
  web_resource_requirements:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
EOF

kubectl apply -f awx-instance.yaml

echo "-------------------------------------------------------"
echo "✅ Installation commands sent!"
echo "-------------------------------------------------------"
echo "🕒 AWX takes 5-10 minutes to build its containers."
echo "🔍 Check status with: kubectl get pods"
echo "🔑 Once running, get your admin password with:"
echo "   kubectl get secret awx-server-admin-password -o jsonpath='{.data.password}' | base64 --decode; echo"
echo "🌐 Find your Web UI port with:"
echo "   kubectl get svc awx-server-service"
echo "-------------------------------------------------------"
