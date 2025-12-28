#!/bin/bash
set -euo pipefail

###############################################################################
# AWX 2.7.2 Installation on Kubernetes (LAB / NON-PROD)
# NodePort | Flannel CNI | Local-Path Storage
###############################################################################

AWX_NAMESPACE="awx"
AWX_NAME="awx-demo"
AWX_OPERATOR_VERSION="2.7.2"
ADMIN_PASSWORD="AdminPassword123"

echo "=== AWX 2.7.2 LAB INSTALLATION STARTED ==="

###############################################################################
# 0. SYSTEM PREP
###############################################################################

echo "[1/9] Disabling firewalld and enabling IP forwarding..."
systemctl stop firewalld || true
systemctl disable firewalld || true
iptables -F || true
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.ipv4.ip_forward=1
systemctl restart containerd || true
systemctl restart kubelet || true

###############################################################################
# 1. INSTALL FLANNEL CNI
###############################################################################

echo "[2/9] Installing Flannel CNI..."
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

echo "[3/9] Installing local-path provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl delete pod -n local-path-storage -l app=local-path-provisioner || true
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true
kubectl get storageclass

###############################################################################
# 3. INSTALL AWX OPERATOR
###############################################################################

echo "[4/9] Installing AWX Operator ${AWX_OPERATOR_VERSION}..."
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
# 4. APPLY KUSTOMIZATION (OPERATOR)
###############################################################################

echo "[5/9] Applying operator kustomization..."
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
# 5. DEPLOY AWX INSTANCE
###############################################################################

echo "[6/9] Deploying AWX instance..."
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
# 6. WAIT FOR AWX PODS
###############################################################################

echo "[7/9] Waiting for AWX pods to become Ready..."
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
# 7. SERVICE & ACCESS INFO
###############################################################################

echo "[8/9] AWX Service Details:"
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
# 8. OPTIONAL DNS TEST
###############################################################################

echo "[9/9] Testing internal DNS (Postgres)..."
kubectl run busybox --image=busybox:1.28 \
  -n ${AWX_NAMESPACE} \
  --rm -it --restart=Never -- \
  nslookup ${AWX_NAME}-postgres-13 || true

echo "=== AWX 2.7.2 LAB INSTALLATION COMPLETE ==="
