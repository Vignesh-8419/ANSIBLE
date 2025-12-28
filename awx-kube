================================================================================
SOP: AWX 2.7.2 Installation on Kubernetes
(NodePort | Flannel CNI | Local-Path Storage | LAB Use)
================================================================================

IMPORTANT NOTES:
- Intended for LAB / NON-PRODUCTION
- Firewall intentionally disabled
- Flannel CNI
- local-path provisioner as default StorageClass
- AWX Operator version: 2.7.2
- Kubernetes v1.30.x compatible
================================================================================

# 1. Disable firewalld temporarily to see if it's the culprit
systemctl stop firewalld
systemctl disable firewalld

# 2. Ensure IP forwarding is enabled (Crucial for Kubernetes)
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.ipv4.ip_forward=1

# 3. Restart the container runtime and kubelet to pick up changes
systemctl restart containerd
systemctl restart kubelet

================================================================================
1. BASE SYSTEM & NETWORK PREPARATION (CONTROL NODE)
================================================================================

# Disable firewall
systemctl stop firewalld
systemctl disable firewalld

# Flush iptables
iptables -F

# Restart kubelet
systemctl restart kubelet


================================================================================
2. INSTALL CNI (FLANNEL)
================================================================================

kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Verify Flannel
kubectl get pods -n kube-system | grep flannel


================================================================================
3. INSTALL LOCAL-PATH STORAGE (DEFAULT STORAGECLASS)
================================================================================

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Restart provisioner for clean state
kubectl delete pod -n local-path-storage -l app=local-path-provisioner

# Watch provisioner logs
kubectl logs -n local-path-storage -l app=local-path-provisioner -f

# Set local-path as default StorageClass
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get storageclass


================================================================================
4. INSTALL AWX OPERATOR (VERSION 2.7.2)
================================================================================

# Create AWX namespace
kubectl create namespace awx

# Install Git
yum install git -y

# Clone operator repo
cd ~
git clone https://github.com/ansible/awx-operator.git
cd awx-operator

# Checkout version 2.7.2
git checkout tag/2.7.2

# Export version
export VERSION=2.7.2

# Deploy operator
make deploy

# OPTIONAL (custom image build)
# IMG=quay.io/<YOUR_NAMESPACE>/awx-operator:<TAG> make deploy

# Create kustomization.yaml
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.7.2

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.7.2

namespace: awx
EOF

kubectl apply -k .

# Set kubectl context
kubectl config set-context --current --namespace=awx


================================================================================
5. DEPLOY AWX INSTANCE
================================================================================

# Create admin password secret
kubectl create secret generic awx-admin-password \
  --from-literal=password='AdminPassword123' \
  -n awx

# Create AWX Custom Resource
cat <<EOF > awx-demo.yml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
spec:
  service_type: nodeport
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

# Create kustomization.yaml for AWX instance
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.7.2
  - awx-demo.yml

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.7.2

namespace: awx
EOF

kubectl apply -k .


================================================================================
6. MONITOR INSTALLATION
================================================================================

# Operator logs
kubectl logs -f deployments/awx-operator-controller-manager -c awx-manager

# Watch pods (expect DB migrations)
kubectl get pods -n awx -w

# Expected state:
# awx-demo-postgres-13-0  → 1/1 Running
# awx-demo-task          → 4/4 Running
# awx-demo-web           → 3/3 Running


================================================================================
7. SERVICE & ACCESS
================================================================================

# Get NodePort
kubectl get svc awx-demo-service -n awx

# Get admin password
kubectl get secret awx-demo-admin-password \
  -o jsonpath="{.data.password}" | base64 --decode ; echo

# Access URL:
# http://<NODE-IP>:<NODE-PORT>
# Username: admin


================================================================================
8. TROUBLESHOOTING & VALIDATION COMMANDS
================================================================================

# Web logs
kubectl logs -f awx-demo-web-6b9898f757-4wkjm -n awx -c awx-demo-web

# Task migration logs
kubectl logs -f awx-demo-task -n awx -c awx-task

# DNS test
kubectl run busybox --image=busybox:1.28 -n awx --rm -it --restart=Never -- \
nslookup awx-demo-postgres-13

# CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Restart CoreDNS if needed
kubectl rollout restart deployment coredns -n kube-system

# Network components
kubectl get pods -n kube-system | grep -E 'flannel|kube-proxy'

# Postgres endpoints
kubectl get endpoints awx-demo-postgres-13 -n awx

# Pod placement
kubectl get pods -n awx -o wide


================================================================================
9. MANUAL DB HOST PATCH (LAST RESORT)
================================================================================

# Replace DB hostname with Cluster IP
kubectl patch secret awx-demo-app-credentials -n awx \
  -p "{\"data\":{\"host\":\"$(echo -n '10.244.2.7' | base64)\"}}"

# Restart all AWX-managed pods
kubectl delete pod -n awx -l "app.kubernetes.io/managed-by=awx-operator"


================================================================================
END OF SOP
================================================================================

kubectl get secret awx-demo-admin-password -n awx -o jsonpath="{.data.password}" | base64 --decode; echo

kubectl get secret awx-demo-admin-password -n awx -o jsonpath="{.data.username}" | base64 --decode; echo
