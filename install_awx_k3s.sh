#!/bin/bash

# --- 1. Environment Setup ---
set -e
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
VIP="192.168.253.145"
ADMIN_PASSWORD="Root@123"
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

rm -rf /etc/yum.repos.d/*
cat <<EOF > /etc/yum.repos.d/internal_mirror.repo
[local-extras]
name=Local Rocky Extras
baseurl=https://http-server-01/repo/offline_repo/extras
enabled=1
gpgcheck=0
sslverify=0

[local-rancher]
name=Local Rancher K3s
baseurl=https://http-server-01/repo/offline_repo/rancher-k3s-common-stable
enabled=1
gpgcheck=0
sslverify=0

[local-packages]
name=Local Core Dependencies
baseurl=https://http-server-01/repo/offline_repo/packages
enabled=1
gpgcheck=0
sslverify=0

[netbox-offline]
name=NetBox Offline Repository
baseurl=https://http-server-01/repo/netbox_offline_repo/rpms
enabled=1
gpgcheck=0
sslverify=0
priority=1
EOF

echo "📦 Installing prerequisites & SELinux support..."
dnf install -y git make curl gettext net-tools container-selinux selinux-policy-base
# Install K3s SELinux policy specifically for RHEL/Rocky 8
dnf install -y https://rpm.rancher.io/k3s/stable/common/centos/8/noarch/k3s-selinux-1.5-1.el8.noarch.rpm || true

# Set SELinux to Permissive for the installation duration to prevent 'event runner' errors
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

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
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
fi

# Link kubectl and set paths
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
export PATH=$PATH:/usr/local/bin
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for K3s to be fully ready
echo "⏳ Waiting for K3s Node to be Ready..."
until kubectl get nodes | grep -q "Ready"; do sleep 5; done

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
echo "⏳ Waiting for Metrics Server..."
until kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; do sleep 5; done
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# --- 6. AWX Operator Deployment ---
echo "🏗️ Deploying AWX Operator..."

# FIXED LINE: We check if the CRD exists first or just allow the command to fail gracefully
kubectl delete awx awx-server -n $NAMESPACE --ignore-not-found=true 2>/dev/null || true

rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git checkout $OPERATOR_VERSION

kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic awx-server-admin-password \
  --from-literal=password=$ADMIN_PASSWORD \
  -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy the operator using the recommended kustomize method
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
echo "⏳ Waiting for AWX UI at http://$VIP..."
echo "Monitoring database & migration status..."

# Loop until we get a 200 OK
until [ "$(curl -s -L -o /dev/null -w "%{http_code}" http://$VIP --connect-timeout 5)" == "200" ]; do
    printf "."
    # Check if pods are stuck in ImagePullBackOff or Error
    STATUS=$(kubectl get pods -n $NAMESPACE | grep "awx-server-postgres" | awk '{print $3}' || echo "Pending")
    if [[ "$STATUS" == *"Error"* ]] || [[ "$STATUS" == *"CrashLoop"* ]]; then
        echo -e "\n⚠️  Postgres pod is in $STATUS state. Check logs with: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=postgres"
    fi
    sleep 15
done

echo -e "\n-------------------------------------------------------"
echo "✅ AWX IS READY!"
echo "🌐 URL: http://$VIP"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "-------------------------------------------------------"
