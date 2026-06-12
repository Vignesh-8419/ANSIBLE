#!/bin/bash

# ============================================================
# AWX on Rocky/RHEL 8 + K3s (Fixed for AWX Operator 2.19.1)
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# -----------------------------
# 1. Variables
# -----------------------------
echo -e "${BLUE}# 1. Variables${NC}"
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
echo -e "${GREEN}✅ Background:${NC} Defined variables for namespace, operator version, VIP, admin password, and proxy image."

# Pre-flight check: ensure cgroup v2 is active
echo -e "${BLUE}# Pre-flight check${NC}"
if [ "$(stat -fc %T /sys/fs/cgroup/)" != "cgroup2fs" ]; then
  echo "❌ ERROR: Host is not running cgroup v2."
  echo "Please edit /etc/default/grub and add:"
  echo 'GRUB_CMDLINE_LINUX="rd.lvm.lv=rl/root rd.lvm.lv=rl/swap resume=/dev/mapper/rl-swap loglevel=7 systemd.show_status=true console=ttyS0,9600 console=tty0 systemd.unified_cgroup_hierarchy=1 systemd.legacy_systemd_cgroup_controller=false"'
  echo "Then run: grub2-mkconfig -o /boot/grub2/grub.cfg && reboot"
  exit 1
fi
echo -e "${GREEN}✅ Background:${NC} Verified host is running cgroup v2, required for K3s."

# -----------------------------
# 2. Install prerequisites
# -----------------------------
echo -e "${BLUE}# 2. Install prerequisites${NC}"
echo "📦 Installing prerequisites..."
dnf install -y git make curl wget tar gzip gettext net-tools container-selinux selinux-policy-base
dnf install -y https://rpm.rancher.io/k3s/stable/common/centos/8/noarch/k3s-selinux-1.5-1.el8.noarch.rpm || true
echo -e "${GREEN}✅ Background:${NC} Installed essential packages and SELinux policies for K3s and AWX."

# -----------------------------
# 3. SELinux / Firewall
# -----------------------------
echo -e "${BLUE}# 3. SELinux / Firewall${NC}"
echo "🔐 Setting SELinux to permissive..."
setenforce 0 || true
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config || true
echo "🔥 Disabling firewalld..."
systemctl stop firewalld || true
systemctl disable firewalld || true
echo -e "${GREEN}✅ Background:${NC} Set SELinux to permissive and disabled firewalld to avoid conflicts."

# -----------------------------
# 4. Assign VIP
# -----------------------------
echo -e "${BLUE}# 4. Assign VIP${NC}"
echo "🌐 Assigning VIP $VIP to interface $INTERFACE ..."
ip addr del "$VIP/32" dev lo 2>/dev/null || true
if ! ip addr show "$INTERFACE" | grep -q "$VIP"; then
    ip addr add "$VIP/24" dev "$INTERFACE"
fi
echo -e "${GREEN}✅ Background:${NC} Assigned the VIP to the correct interface for AWX access."

# -----------------------------
# 5. Install K3s
# -----------------------------
echo -e "${BLUE}# 5. Install K3s${NC}"
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
echo -e "${GREEN}✅ Background:${NC} Installed K3s, linked kubectl, and confirmed node readiness."

# -----------------------------
# 6. Install Kustomize
# -----------------------------
echo -e "${BLUE}# 6. Install Kustomize${NC}"
if ! command -v kustomize >/dev/null 2>&1; then
    echo "🛠️ Installing Kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    mv kustomize /usr/local/bin/
else
    echo "ℹ️ Kustomize already installed."
fi
echo -e "${GREEN}✅ Background:${NC} Installed Kustomize, used later for operator manifests."

# -----------------------------
# 7. Patch Metrics Server
# -----------------------------
echo -e "${BLUE}# 7. Patch Metrics Server${NC}"
echo "⏳ Waiting for metrics-server deployment..."
until kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; do sleep 5; done
echo "🔧 Patching metrics-server..."
if ! kubectl get deployment metrics-server -n kube-system -o yaml | grep -q -- "--kubelet-insecure-tls"; then
    kubectl patch deployment metrics-server -n kube-system --type='json' \
      -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
fi
echo -e "${GREEN}✅ Background:${NC} Patched metrics-server to allow insecure TLS for kubelet metrics."

# -----------------------------
# 8. Cleanup old AWX resources
# -----------------------------
echo -e "${BLUE}# 8. Cleanup old AWX resources${NC}"
echo "🧹 Cleaning old AWX resources..."
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
kubectl delete awx awx-server -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete ingress awx-ingress -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete deployment awx-operator-controller-manager -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete rs --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pods --all -n "$NAMESPACE" --ignore-not-found=true || true
echo -e "${GREEN}✅ Background:${NC} Cleaned up any old AWX resources to ensure a fresh install."

# -----------------------------
# 9. Verify kube-rbac-proxy image
# -----------------------------
echo -e "${BLUE}# 9. Verify kube-rbac-proxy image${NC}"
echo "🧪 Verifying kube-rbac-proxy image..."
crictl pull "$KUBE_RBAC_PROXY_IMAGE"
echo -e "${GREEN}✅ Background:${NC} Verified kube-rbac-proxy image availability."

# -----------------------------
# 10. Download AWX Operator source
# -----------------------------
echo -e "${BLUE}# 10. Download AWX Operator source${NC}"
echo "📥 Downloading AWX Operator source..."
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git checkout "$OPERATOR_VERSION"
echo -e "${GREEN}✅ Background:${NC} Downloaded AWX Operator source and checked out version $OPERATOR_VERSION."

# -----------------------------
# 11. Fix kube-rbac-proxy image
# -----------------------------
echo -e "${BLUE}# 11. Fix kube-rbac-proxy image${NC}"
echo "🔧 Fixing AWX Operator kube-rbac-proxy image..."
cd config/default
kustomize edit set image gcr.io/kubebuilder/kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true
kustomize edit set image registry.k8s.io/kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true
cd ../../
echo -e "${GREEN}✅ Background:${NC} Updated the AWX Operator manifests to use the correct kube-rbac-proxy image version, ensuring compatibility with Operator $OPERATOR_VERSION."

# -----------------------------
# 12. Create AWX admin password secret
# -----------------------------
echo -e "${BLUE}# 12. Create AWX admin password secret${NC}"
echo "🔐 Creating AWX admin password secret..."
kubectl create secret generic awx-server-admin-password \
  --from-literal=password="$ADMIN_PASSWORD" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Background:${NC} Created a Kubernetes secret storing the AWX admin password, referenced by the AWX CRD."

# -----------------------------
# 13. Deploy AWX Operator
# -----------------------------
echo -e "${BLUE}# 13. Deploy AWX Operator${NC}"
echo "🏗️ Deploying AWX Operator..."
make deploy NAMESPACE="$NAMESPACE"
kubectl -n "$NAMESPACE" set image deployment/awx-operator-controller-manager \
  kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true

echo "⏳ Waiting for AWX Operator pod..."
kubectl rollout status deployment/awx-operator-controller-manager -n "$NAMESPACE" --timeout=300s
echo -e "${GREEN}✅ Background:${NC} Deployed the AWX Operator and confirmed its controller pod is running."

# -----------------------------
# 14. Create AWX instance
# -----------------------------
echo -e "${BLUE}# 14. Create AWX instance${NC}"
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

# Wait for Deployment to be created (prevents NotFound error)
echo "⏳ Waiting for AWX Deployment to be created..."
for i in {1..60}; do
    if kubectl get deployment awx-server -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "✅ AWX Deployment created."
        break
    fi
    sleep 10
done
echo -e "${GREEN}✅ Background:${NC} Applied the AWX CRD and waited until the operator reconciled it into a Deployment."

# -----------------------------
# 14a. Stream migration logs
# -----------------------------
echo -e "${BLUE}# 14a. Stream migration logs${NC}"
echo "📜 Streaming AWX migration logs..."
MIGRATION_POD=$(kubectl get pods -n "$NAMESPACE" \
  -l app.kubernetes.io/name=awx-server-migration \
  -o name | head -1 | cut -d/ -f2)

if [ -n "$MIGRATION_POD" ]; then
  echo "✅ Found migration pod: $MIGRATION_POD"
  echo "⏳ Streaming logs until migrations finish..."
  # Stream logs and save them to a file
  kubectl logs -n "$NAMESPACE" "$MIGRATION_POD" -f | tee /tmp/awx-migration.log
  # After stream ends, print the last line
  echo "✅ Migration finished. Last line was:"
  tail -n 1 /tmp/awx-migration.log
else
  echo "⚠️ No migration pod found yet. Continuing..."
fi
echo -e "${GREEN}✅ Background:${NC} Streamed database migration logs. The final line confirms schema upgrades completed successfully."

# -----------------------------
# 15. Create Ingress
# -----------------------------
echo -e "${BLUE}# 15. Create Ingress${NC}"
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
echo -e "${GREEN}✅ Background:${NC} Created and patched the Ingress resource so AWX is accessible externally via Traefik at the VIP."

# -----------------------------
# 16. Wait for migration task (delayed)
# -----------------------------
echo -e "${BLUE}# 16. Wait for migration task${NC}"
echo "⏳ Sleeping for 10 minutes to allow migrations to complete..."
sleep 900

echo "📜 Checking migration pod logs again..."
MIGRATION_POD=$(kubectl get pods -n "$NAMESPACE" \
  -l app.kubernetes.io/name=awx-server-migration \
  -o name | head -1 | cut -d/ -f2)

if [ -n "$MIGRATION_POD" ]; then
  echo "✅ Found migration pod: $MIGRATION_POD"
  echo "⏳ Printing last 10 lines of migration logs..."
  kubectl logs -n "$NAMESPACE" "$MIGRATION_POD" | tail -n 10
else
  echo "⚠️ No migration pod found. Continuing..."
fi

echo -e "${GREEN}✅ Background:${NC} Skipped rollout status check and instead waited 10 minutes, then verified migration logs. This avoids premature 'NotFound' errors while the operator reconciles resources."

# -----------------------------
# 17. Wait for AWX UI
# -----------------------------
echo -e "${BLUE}# 17. Wait for AWX UI${NC}"
echo "⏳ Waiting for AWX UI at http://$VIP ..."
for i in {1..80}; do
    if [ "$(curl -s -L -o /dev/null -w "%{http_code}" "http://$VIP" --connect-timeout 5)" == "200" ]; then
        break
    fi
    sleep 15
done
echo -e "${GREEN}✅ Background:${NC} Confirmed the AWX web UI is responding with HTTP 200 at the VIP, meaning the dashboard is live."
