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

# -----------------------------
# 2. Install prerequisites
# -----------------------------
echo "📦 Installing prerequisites..."
dnf install -y git make curl wget tar gzip gettext net-tools container-selinux selinux-policy-base

echo "📦 Installing K3s SELinux policy (best effort)..."
dnf install -y https://rpm.rancher.io/k3s/stable/common/centos/8/noarch/k3s-selinux-1.5-1.el8.noarch.rpm || true

# -----------------------------
# 3. SELinux / Firewall
# -----------------------------
echo "🔐 Setting SELinux to permissive (lab-friendly)..."
setenforce 0 || true
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config || true

echo "🔥 Disabling firewalld (lab-friendly)..."
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
until kubectl get nodes 2>/dev/null | grep -q " Ready "; do
    sleep 5
done

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
until kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; do
    sleep 5
done

echo "🔧 Patching metrics-server with --kubelet-insecure-tls (if not already set)..."
if ! kubectl get deployment metrics-server -n kube-system -o yaml | grep -q -- "--kubelet-insecure-tls"; then
    kubectl patch deployment metrics-server -n kube-system --type='json' \
      -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
else
    echo "ℹ️ metrics-server already patched."
fi

# -----------------------------
# 8. Cleanup old AWX resources (safe)
# -----------------------------
echo "🧹 Cleaning old AWX resources (best effort)..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete awx awx-server -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete ingress awx-ingress -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete deployment awx-operator-controller-manager -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete rs --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pods --all -n "$NAMESPACE" --ignore-not-found=true || true

# -----------------------------
# 9. Verify working kube-rbac-proxy image
# -----------------------------
echo "🧪 Verifying kube-rbac-proxy image..."
if ! crictl pull "$KUBE_RBAC_PROXY_IMAGE"; then
    echo "❌ Failed to pull $KUBE_RBAC_PROXY_IMAGE"
    exit 1
fi
echo "✅ Verified working image: $KUBE_RBAC_PROXY_IMAGE"

# -----------------------------
# 10. Download AWX Operator source
# -----------------------------
echo "📥 Downloading AWX Operator source..."
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git checkout "$OPERATOR_VERSION"

# -----------------------------
# 11. Fix broken kube-rbac-proxy image in kustomize
# -----------------------------
echo "🔧 Fixing AWX Operator kube-rbac-proxy image..."
cd config/default

# Try replacing old gcr.io reference (used by this version in many cases)
kustomize edit set image gcr.io/kubebuilder/kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true

# Also try replacing registry.k8s.io if present
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

echo "⏳ Waiting for AWX Operator deployment object..."
until kubectl get deployment awx-operator-controller-manager -n "$NAMESPACE" >/dev/null 2>&1; do
    sleep 3
done

# Safety patch after deploy (ensures image is correct even if kustomize replacement missed)
echo "🔧 Applying safety patch to AWX Operator deployment..."
kubectl -n "$NAMESPACE" set image deployment/awx-operator-controller-manager \
  kube-rbac-proxy="$KUBE_RBAC_PROXY_IMAGE" || true

echo "⏳ Waiting for AWX Operator pod to become 2/2 Running..."
OP_ATTEMPTS=0
OP_MAX_ATTEMPTS=60   # 60 x 5 sec = 5 min

until kubectl get pods -n "$NAMESPACE" | grep awx-operator-controller-manager | grep -q "2/2.*Running"; do
    OP_ATTEMPTS=$((OP_ATTEMPTS+1))
    echo "---- Operator pod status ----"
    kubectl get pods -n "$NAMESPACE" || true

    if kubectl get pods -n "$NAMESPACE" | grep awx-operator-controller-manager | grep -Eq "ImagePullBackOff|ErrImagePull|CrashLoopBackOff|Error"; then
        echo "❌ AWX Operator pod unhealthy. Showing details..."
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -o name | grep awx-operator-controller-manager | head -1 | cut -d/ -f2)
        kubectl describe pod "$POD_NAME" -n "$NAMESPACE" || true
        exit 1
    fi

    if [ "$OP_ATTEMPTS" -ge "$OP_MAX_ATTEMPTS" ]; then
        echo "❌ Timeout waiting for AWX Operator to become healthy."
        kubectl get pods -n "$NAMESPACE"
        exit 1
    fi

    sleep 5
done

echo "✅ AWX Operator is healthy."
kubectl get pods -n "$NAMESPACE"

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
# 15. Create Ingress (Traefik in K3s)
# -----------------------------
echo "🔗 Creating Ingress for AWX..."
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

# Optional TLS annotation patch (kept from your script, but HTTP is enough)
kubectl patch ingress awx-ingress -n "$NAMESPACE" --type='merge' -p "
{
  \"metadata\": {
    \"annotations\": {
      \"traefik.ingress.kubernetes.io/router.entrypoints\": \"web,websecure\"
    }
  }
}" || true

# -----------------------------
# 16. Wait for AWX pods
# -----------------------------
echo "⏳ Waiting for AWX pods to become healthy..."
AWX_ATTEMPTS=0
AWX_MAX_ATTEMPTS=80   # ~20 minutes

until kubectl get pods -n "$NAMESPACE" | grep -q "awx-server-web.*3/3.*Running"; do
    AWX_ATTEMPTS=$((AWX_ATTEMPTS+1))

    echo "---- AWX pod status ----"
    kubectl get pods -n "$NAMESPACE" || true

    # Fail early if operator breaks
    if kubectl get pods -n "$NAMESPACE" | grep awx-operator-controller-manager | grep -Eq "ImagePullBackOff|ErrImagePull|CrashLoopBackOff|Error"; then
        echo "❌ Operator unhealthy after AWX creation."
        kubectl get pods -n "$NAMESPACE"
        exit 1
    fi

    # Fail early if postgres breaks
    if kubectl get pods -n "$NAMESPACE" | grep awx-server-postgres | grep -Eq "Error|CrashLoopBackOff"; then
        echo "❌ Postgres unhealthy. Showing logs..."
        kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=postgres --tail=100 || true
        exit 1
    fi

    if [ "$AWX_ATTEMPTS" -ge "$AWX_MAX_ATTEMPTS" ]; then
        echo "❌ Timeout waiting for AWX web pod."
        kubectl get pods -n "$NAMESPACE"
        exit 1
    fi

    sleep 15
done

echo "✅ AWX web pod is running."

# Optional: wait for task pod too
echo "⏳ Waiting for AWX task pod..."
TASK_ATTEMPTS=0
TASK_MAX_ATTEMPTS=40

until kubectl get pods -n "$NAMESPACE" | grep -q "awx-server-task.*4/4.*Running"; do
    TASK_ATTEMPTS=$((TASK_ATTEMPTS+1))
    kubectl get pods -n "$NAMESPACE" || true

    if [ "$TASK_ATTEMPTS" -ge "$TASK_MAX_ATTEMPTS" ]; then
        echo "⚠️ Timeout waiting for task pod, but continuing. Check manually:"
        echo "   kubectl get pods -n $NAMESPACE"
        break
    fi

    sleep 10
done

# -----------------------------
# 17. Wait for AWX UI
# -----------------------------
echo "⏳ Waiting for AWX UI at http://$VIP ..."
UI_ATTEMPTS=0
UI_MAX_ATTEMPTS=80   # ~20 minutes

until [ "$(curl -s -L -o /dev/null -w "%{http_code}" "http://$VIP" --connect-timeout 5)" == "200" ]; do
    UI_ATTEMPTS=$((UI_ATTEMPTS+1))
    printf "."

    if [ $((UI_ATTEMPTS % 4)) -eq 0 ]; then
        echo
        kubectl get pods -n "$NAMESPACE" || true
        kubectl get ingress -n "$NAMESPACE" || true
        kubectl get svc -n "$NAMESPACE" || true
    fi

    if [ "$UI_ATTEMPTS" -ge "$UI_MAX_ATTEMPTS" ]; then
        echo
        echo "⚠️ AWX pods are up, but UI not reachable yet via VIP."
        echo "Check these manually:"
        echo "  kubectl get ingress -n $NAMESPACE"
        echo "  kubectl describe ingress awx-ingress -n $NAMESPACE"
        echo "  kubectl get svc -n $NAMESPACE"
        break
    fi

    sleep 15
done

echo

# -----------------------------
# 18. Final output
# -----------------------------
echo "-------------------------------------------------------"
echo "✅ AWX installation completed (or mostly ready)"
echo "🌐 URL: http://$VIP"
echo "👤 User: admin"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "-------------------------------------------------------"

echo "📌 Useful checks:"
echo "kubectl get pods -n $NAMESPACE"
echo "kubectl get svc -n $NAMESPACE"
echo "kubectl get ingress -n $NAMESPACE"
echo "kubectl get secret awx-server-admin-password -n $NAMESPACE -o jsonpath=\"{.data.password}\" | base64 -d ; echo"
