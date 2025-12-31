#!/bin/bash
set -euo pipefail

# ========================
# 1️⃣ System Preparation
# ========================
#dnf update -y

# Disable firewall and SELinux
systemctl stop firewalld
systemctl disable firewalld
setenforce 0
getenforce

# Install required utilities
dnf install -y yum-utils git curl wget jq vim net-tools

# ========================
# 2️⃣ Install Docker
# ========================
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io
systemctl start docker
systemctl enable docker

# ========================
# 3️⃣ Install Kubernetes Components
# ========================
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=0
EOF

dnf install -y kubelet kubeadm kubectl
systemctl enable --now kubelet

# ========================
# 4️⃣ Apply Kernel & Networking Fixes (Flannel) to All Nodes
# ========================
WORKER_NODES=("worker-01" "worker-02") # Replace with your worker node hostnames/IPs

# Apply on control plane
modprobe br_netfilter
echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.bridge.bridge-nf-call-ip6tables=1
sysctl -w net.ipv4.ip_forward=1
cat <<EOF >> /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# Apply on workers
for NODE in "${WORKER_NODES[@]}"; do
  ssh root@"$NODE" bash -s <<'EOF'
modprobe br_netfilter
echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.bridge.bridge-nf-call-ip6tables=1
sysctl -w net.ipv4.ip_forward=1
cat <<EOT >> /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOT
sysctl --system
systemctl restart kubelet
EOF
done

# ========================
# 5️⃣ Initialize Kubernetes
# ========================
kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl for root
export KUBECONFIG=/etc/kubernetes/admin.conf

# Allow scheduling pods on the control-plane node
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# ========================
# 6️⃣ Install Flannel CNI
# ========================
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Wait until Flannel pods are ready
echo "Waiting for Flannel pods..."
for i in {1..30}; do
    NOT_READY=$(kubectl get pods -n kube-flannel -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep false || true)
    if [[ -z "$NOT_READY" ]]; then
        echo "Flannel is Ready"
        break
    fi
    echo "Waiting for Flannel... (${i}/30)"
    sleep 5
done

kubectl get pods -n kube-flannel -o wide

# ========================
# 7️⃣ Install Local Path Storage
# ========================
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass

# ========================
# 8️⃣ Deploy AWX Operator
# ========================
kubectl create namespace awx
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml
kubectl get pods -n awx

# ========================
# 9️⃣ Deploy AWX Instance
# ========================
cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
  namespace: awx
spec:
  service_type: NodePort
EOF

kubectl get pods -n awx -o wide
kubectl get svc -n awx

# ========================
# 🔟 Optional: Longhorn (Persistent Storage)
# ========================
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
kubectl get pods -n longhorn-system

# Port-forward Longhorn UI
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80
