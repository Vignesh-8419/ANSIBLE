# ========================
# 1️⃣ System Preparation
# ========================
dnf update -y

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
# 4️⃣ Initialize Kubernetes
# ========================
kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl for root
export KUBECONFIG=/etc/kubernetes/admin.conf

# Allow scheduling pods on the control-plane node
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# ========================
# 5️⃣ Install Flannel CNI
# ========================
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Verify Flannel pods
kubectl get pods -n kube-flannel -o wide

# ========================
# 6️⃣ Install Local Path Storage
# ========================
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass

# ========================
# 7️⃣ Deploy AWX Operator
# ========================
kubectl create namespace awx
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml
kubectl get pods -n awx

# ========================
# 8️⃣ Deploy AWX Instance
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

# Example: Access AWX UI at http://<node-ip>:<NodePort>

# ========================
# 9️⃣ Optional: Longhorn (Persistent Storage)
# ========================
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
kubectl get pods -n longhorn-system

# Forward Longhorn UI to local machine
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80
