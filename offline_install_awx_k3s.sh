#!/bin/bash

# --- 1. Environment Setup ---
set -e
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
VIP="192.168.253.145"
ADMIN_PASSWORD="Root@123"
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

# --- Pre-Flight Port Check ---
if netstat -tulpn | grep -q ":6443"; then
    echo "⚠️ Port 6443 is already in use. Cleaning up..."
    systemctl stop k3s || true
    pkill -9 k3s || true
    sleep 2
fi

# Refresh Repositories
rm -rf /etc/yum.repos.d/*
cat <<EOF > /etc/yum.repos.d/internal_mirror.repo
[local-extras]
name=Local Rocky Extras
baseurl=https://http-server-01/repo/ansible_offline_repo/extras
enabled=1
gpgcheck=0
sslverify=0

[local-rancher]
name=Local Rancher K3s
baseurl=https://http-server-01/repo/ansible_offline_repo/rancher-k3s-common-stable
enabled=1
gpgcheck=0
sslverify=0

[local-packages]
name=Local Core Dependencies
baseurl=https://http-server-01/repo/ansible_offline_repo/packages
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
dnf install -y https://rpm.rancher.io/k3s/stable/common/centos/8/noarch/k3s-selinux-1.5-1.el8.noarch.rpm || true

# Set SELinux to Permissive for the installation duration
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

# Fallback mechanism: Try installer, if fails, do it manually
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh - || true
fi

# Manual Binary Download if installer skipped or failed
if [ ! -f /usr/local/bin/k3s ]; then
    echo "⚠️ Installer failed to place binary. Downloading manually..."
    curl -Lo /usr/local/bin/k3s https://github.com/k3s-io/k3s/releases/download/v1.29.1+k3s2/k3s
    chmod +x /usr/local/bin/k3s
fi

# Manual Service Creation if missing
if [ ! -f /etc/systemd/system/k3s.service ]; then
    echo "🛠️ Creating k3s.service manually..."
    cat <<EOF > /etc/systemd/system/k3s.service
[Unit]
Description=Lightweight Kubernetes
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/k3s server --write-kubeconfig-mode 644
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl enable --now k3s

echo "⏳ Waiting for K3s configuration file..."
until [ -f /etc/rancher/k3s/k3s.yaml ]; do
    sleep 2
    printf "."
done

# Set Environment for the script
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH=$PATH:/usr/local/bin
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

echo -e "\n⏳ Waiting for K3s Node to be Ready..."
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
echo "⏳ Waiting for AWX UI at http://$VIP..."
echo "Monitoring migration status..."

until [ "$(curl -s -L -o /dev/null -w "%{http_code}" http://$VIP --connect-timeout 5)" == "200" ]; do
    printf "."
    STATUS=$(kubectl get pods -n $NAMESPACE | grep "postgres" | awk '{print $3}' | head -n 1 || echo "Pending")
    if [[ "$STATUS" == *"Error"* ]] || [[ "$STATUS" == *"CrashLoop"* ]]; then
        echo -e "\n⚠️  Postgres error: Check logs with 'kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=postgres'"
    fi
    sleep 20
done

cat <<EOF | kubectl apply -f -
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
  namespace: awx
spec:
  redirectScheme:
    scheme: https
    permanent: true
EOF

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: awx-ingress
  namespace: awx
  annotations:
    # This line triggers the redirect middleware created above
    traefik.ingress.kubernetes.io/router.middlewares: awx-redirect-https@kubernetescrd
    # This line tells Traefik to listen on both ports
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
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

echo -e "\n-------------------------------------------------------"
echo "✅ AWX IS READY!"
echo "🌐 URL: http://$VIP"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "-------------------------------------------------------"
