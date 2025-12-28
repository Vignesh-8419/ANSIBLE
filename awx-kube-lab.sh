#!/bin/bash
set -euo pipefail

###############################################################################
# AWX 2.7.2 Full Installation on Kubernetes (LAB / NON-PROD)
# NodePort | Flannel CNI | Local-Path Storage
# Includes DNS fix for CoreDNS / Postgres connectivity
###############################################################################

AWX_NAMESPACE="awx"
AWX_NAME="awx-demo"
AWX_OPERATOR_VERSION="2.7.2"
ADMIN_PASSWORD="AdminPassword123"
DNS_SERVER="192.168.253.151"

echo "=== AWX 2.7.2 FULL LAB INSTALLATION STARTED ==="

###############################################################################
# 0. SYSTEM PREP
###############################################################################

echo "[1/11] Disabling firewall, enabling IP forwarding, loading br_netfilter, and fixing DNS..."
systemctl stop firewalld || true
systemctl disable firewalld || true
iptables -F || true

# Load br_netfilter module (required for Flannel)
modprobe br_netfilter
echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf

# Enable forwarding and bridge-nf for Kubernetes networking
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.bridge.bridge-nf-call-ip6tables=1
sysctl -w net.ipv4.ip_forward=1

# Persist sysctl settings
cat <<EOF >> /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# Set internal DNS
cp -a /etc/resolv.conf /etc/resolv.conf.bak.$(date +%F_%T)
cat <<EOF | tee /etc/resolv.conf
search localdomain vgs.com
nameserver ${DNS_SERVER}
EOF
chmod 644 /etc/resolv.conf

# Restart containerd and kubelet to pick up network changes
systemctl restart containerd || true
systemctl restart kubelet || true

###############################################################################
# 1. INSTALL FLANNEL CNI
###############################################################################

echo "[2/11] Installing Flannel CNI..."
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "Waiting for Flannel pods to become Ready..."
for i in {1..30}; do
    NOT_READY=$(kubectl get pods -n kube-flannel -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep false || true)
    if [[ -z "$NOT_READY" ]]; then
        echo "Flannel is Ready"
        break
    fi
    echo "Waiting for Flannel... (${i}/30)"
    sleep 5
done

###############################################################################
# 2. INSTALL LOCAL-PATH STORAGE
###############################################################################

echo "[3/11] Installing Local-Path Provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl delete pod -n local-path-storage -l app=local-path-provisioner || true
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true
kubectl get storageclass

###############################################################################
# 3. FIX COREDNS (if already deployed)
###############################################################################

echo "[4/11] Deleting broken CoreDNS pods..."
kubectl delete pod -n kube-system -l k8s-app=kube-dns --ignore-not-found || true
echo "Waiting for CoreDNS to restart..."
kubectl wait --for=condition=Ready pod -n kube-system -l k8s-app=kube-dns --timeout=300s || true

###############################################################################
# 4. INSTALL AWX OPERATOR
###############################################################################

echo "[5/11] Installing AWX Operator ${AWX_OPERATOR_VERSION}..."
kubectl create namespace ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

dnf install -y git make || true

cd /root || exit 1
rm -rf awx-operator
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git checkout ${AWX_OPERATOR_VERSION}

export VERSION=${AWX_OPERATOR_VERSION}
make deploy

###############################################################################
# 5. APPLY OPERATOR KUSTOMIZATION
###############################################################################

echo "[6/11] Applying operator kustomization..."
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}

images:
  - name: quay.io/ansible/awx-operator
    newTag: ${AWX_OPERATOR_VERSION}

namespace: ${AWX_NAMESPACE}
EOF

kubectl apply -k .
kubectl config set-context --current --namespace=${AWX_NAMESPACE}

###############################################################################
# 6. DEPLOY AWX INSTANCE
###############################################################################

echo "[7/11] Deploying AWX instance..."
kubectl create secret generic awx-admin-password \
  --from-literal=password="${ADMIN_PASSWORD}" \
  -n ${AWX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF > awx-demo.yml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ${AWX_NAME}
spec:
  service_type: NodePort
  web_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 4Gi
  task_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 4Gi
EOF

cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - awx-demo.yml

namespace: ${AWX_NAMESPACE}
EOF

kubectl apply -k .

###############################################################################
# 7. WAIT FOR AWX PODS
###############################################################################

echo "[8/11] Waiting for AWX pods to become Ready..."
# Wait until all pods exist
while [[ $(kubectl get pods -n ${AWX_NAMESPACE} --no-headers | wc -l) -lt 3 ]]; do
    echo "Pods not yet created, waiting..."
    sleep 5
done

# Wait for task, web, and postgres pods individually
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=task -n ${AWX_NAMESPACE} --timeout=900s || true
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=web -n ${AWX_NAMESPACE} --timeout=900s || true
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=database -n ${AWX_NAMESPACE} --timeout=900s || true

kubectl get pods -n ${AWX_NAMESPACE}

###############################################################################
# 8. SERVICE & ACCESS INFO
###############################################################################

echo "[9/11] AWX Service Details:"
# Wait until the NodePort service exists
until kubectl get svc ${AWX_NAME}-service -n ${AWX_NAMESPACE} &> /dev/null; do
    echo "Waiting for AWX NodePort service..."
    sleep 5
done

kubectl get svc ${AWX_NAME}-service -n ${AWX_NAMESPACE}

echo
echo "Admin password:"
kubectl get secret ${AWX_NAME}-admin-password \
  -n ${AWX_NAMESPACE} \
  -o jsonpath="{.data.password}" | base64 --decode
echo

###############################################################################
# 9. OPTIONAL DNS TEST
###############################################################################

echo "[10/11] Testing internal DNS (Postgres)..."
kubectl run busybox --image=busybox:1.28 \
  -n ${AWX_NAMESPACE} \
  --rm -it --restart=Never -- \
  nslookup ${AWX_NAME}-postgres-13 || true

###############################################################################
# 10. FINAL CHECKS
###############################################################################

echo "[11/11] Final checks for CoreDNS and AWX pods..."
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get pods -n ${AWX_NAMESPACE}

echo "=== AWX 2.7.2 FULL LAB INSTALLATION COMPLETE ==="
