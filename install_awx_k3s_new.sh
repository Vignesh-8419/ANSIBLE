#!/bin/bash

# ============================================================
# AWX on Rocky/RHEL 8 + K3s (Fixed for AWX Operator 2.19.1)
# ============================================================

set -euo pipefail

# -----------------------------
# 1. Variables
# -----------------------------
NAMESPACE="awx"
OPERATOR_VERSION="2.19.1"
VIP="192.168.253.145"
ADMIN_PASSWORD="Root@123"
KUBE_RBAC_PROXY_IMAGE="quay.io/brancz/kube-rbac-proxy:v0.18.0"

INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

echo "============================================================"
echo "🚀 Starting AWX installation on K3s"
echo "Namespace           : $NAMESPACE"
echo "Operator Version    : $OPERATOR_VERSION"
echo "VIP                 : $VIP"
echo "Interface           : $INTERFACE"
echo "kube-rbac-proxy     : $KUBE_RBAC_PROXY_IMAGE"
echo "============================================================"


# Pre-flight check: ensure cgroup v2 is active
if [ "$(stat -fc %T /sys/fs/cgroup/)" != "cgroup2fs" ]; then
  echo "❌ ERROR: Host is not running cgroup v2."
  echo "Please edit /etc/default/grub and add:"
  echo 'GRUB_CMDLINE_LINUX="rd.lvm.lv=rl/root rd.lvm.lv=rl/swap resume=/dev/mapper/rl-swap loglevel=7 systemd.show_status=true console=ttyS0,9600 console=tty0 systemd.unified_cgroup_hierarchy=1 systemd.legacy_systemd_cgroup_controller=false"
'
  echo "Then run: grub2-mkconfig -o /boot/grub2/grub.cfg && reboot"
  exit 1
fi

  
# -----------------------------
# 2. Install prerequisites
# -----------------------------
echo "📦 Installing prerequisites..."
dnf install -y git make curl wget tar gzip gettext net-tools container-selinux selinux-policy-base
dnf install -y https://rpm.rancher.io/k3s/stable/common/centos/8/noarch/k3s-selinux-1.5-1.el8.noarch.rpm || true

# -----------------------------
# 3. SELinux / Firewall
# -----------------------------
echo "🔐 Setting SELinux to permissive..."
setenforce 0 || true
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config || true
echo "🔥 Disabling firewalld..."
systemctl stop firewalld || true
systemctl disable firewalld || true

# -----------------------------
# 4. Assign VIP
# -----------------------------
echo "🌐 Assigning VIP $VIP to interface $INTERFACE ..."
ip addr del "$VIP/32" dev lo 2>/dev/null || true
if ! ip addr show "$INTERFACE" | grep -q "$VIP"; then
    ip addr add "$VIP/24" dev "$INTERFACE"
fi

# -----------------------------
# 5. Install K3s
# -----------------------------
echo "☸️ Installing K3s..."
if ! command -v k3s >/dev/null 2>&1; then
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
else
    echo "ℹ️ K3s already installed, skipping."
fi

echo "🔗 Linking kubectl..."
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
export PATH=$PATH:/usr/local/bin
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "⏳ Waiting for K3s node to be Ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready "; do sleep 5; done

mkdir -p "$HOME/.kube"
cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
echo "✅ K3s is ready."
kubectl get nodes

# -----------------------------
# 6. Install Kustomize
# -----------------------------
if ! command -v kustomize >/dev/null 2>&1; then
    echo "🛠️ Installing Kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    mv kustomize /usr/local/bin/
else
    echo "ℹ️ Kustomize already installed."
fi

# -----------------------------
# 7. Patch Metrics Server
# -----------------------------
echo "⏳ Waiting for metrics-server deployment..."
until kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; do sleep 5; done
echo "🔧 Patching metrics-server..."
if ! kubectl get deployment metrics-server -n kube-system -o yaml | grep -q -- "--kubelet-insecure-tls"; then
    kubectl patch deployment metrics-server -n kube-system --type='json' \
      -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
fi

# -----------------------------
# 8. Cleanup old AWX resources
# -----------------------------
echo "🧹 Cleaning old AWX resources..."
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
kubectl delete awx awx-server -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete ingress awx-ingress -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete deployment awx-operator-controller-manager -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete rs --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pods --all -n "$NAMESPACE" --ignore-not-found=true || true

# -----------------------------
# 9. Verify kube-rbac-proxy image
# -----------------------------
echo "🧪 Verifying kube-rbac-proxy image..."
crictl pull "$KUBE_RBAC_PROXY_IMAGE"

# -----------------------------
# 10. Download AWX Operator source
# -----------------------------
echo "📥 Downloading AWX Operator source..."
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git checkout "$OPERATOR_VERSION"

# -----------------------------
# 11. Fix kube-rbac-proxy image
# -----------------------------
echo "🔧 Fixing AWX Operator kube-rbac-proxy image..."
cd config/default
kustomize edit set image gcr.io/kubebuilder/kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true
kustomize edit set image registry.k8s.io/kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true
cd ../../

# -----------------------------
# 12. Create AWX admin password secret
# -----------------------------
echo "🔐 Creating AWX admin password secret..."
kubectl create secret generic awx-server-admin-password \
  --from-literal=password="$ADMIN_PASSWORD" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------
# 13. Deploy AWX Operator
# -----------------------------
echo "🏗️ Deploying AWX Operator..."
make deploy NAMESPACE="$NAMESPACE"
kubectl -n "$NAMESPACE" set image deployment/awx-operator-controller-manager \
  kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true

echo "⏳ Waiting for AWX Operator pod..."
kubectl rollout status deployment/awx-operator-controller-manager -n "$NAMESPACE" --timeout=300s

# -----------------------------
# 14. Create AWX instance
# -----------------------------
echo "🚀 Creating AWX instance..."
cat <<EOF > awx-instance.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-server
  namespace: $NAMESPACE
spec:
  service_type: ClusterIP
  admin_password_secret: awx-server-admin-password
  postgres_storage_class: local-path
EOF
kubectl apply -f awx-instance.yaml

# -----------------------------
# 15. Create Ingress
# -----------------------------
echo "🔗 Creating Ingress for AWX..."
cat <<EOF > awx-ingress.yaml
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
kubectl apply -f awx-ingress.yaml
kubectl patch ingress awx-ingress -n "$NAMESPACE" --type='merge' -p \
'{"metadata":{"annotations":{"traefik.ingress.kubernetes.io/router.entrypoints":"web,websecure"}}}' || true

# -----------------------------
# 16. Wait for AWX pods
# -----------------------------
echo "⏳ Waiting for AWX pods..."
kubectl rollout status deployment/awx-server -n "$NAMESPACE" --timeout=1200s

# -----------------------------
# 17. Wait for AWX UI
# -----------------------------
echo "⏳ Waiting for AWX UI at http://$VIP ..."
for i in {1..80}; do
    if [ "$(curl -s -L -o /dev/null -w "%{http_code}" "http://$VIP" --connect-timeout 5)" == "200" ]; then
        break
    fi
    sleep 15
done

# -----------------------------
# 
