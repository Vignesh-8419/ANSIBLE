#!/bin/bash
set -euo pipefail

echo "[Step 1] Disable swap..."
sudo sed -i '/swap/d' /etc/fstab
sudo swapoff -a

echo "[Step 2] Enable kernel modules..."
sudo modprobe overlay
sudo modprobe br_netfilter

echo "[Step 3] Set sysctl params..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

echo "[Step 4] Add Kubernetes repo..."
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
EOF

echo "[Step 5] Install kubeadm, kubelet, kubectl..."
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

echo "[Step 6] Install native containerd..."
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum remove runc -y
sudo dnf remove -y containerd.io || true
sudo dnf install -y containerd iproute-tc

echo "[Step 7] Configure containerd..."
sudo mkdir -p /etc/containerd
sudo rm -f /etc/containerd/config.toml
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Patch config for Kubernetes
sudo sed -i 's|sandbox_image = .*|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
sudo sed -i 's|systemd_cgroup = true|systemd_cgroup = false|' /etc/containerd/config.toml
sudo sed -i 's|runtime_type = ""|runtime_type = "io.containerd.runc.v2"|' /etc/containerd/config.toml
sudo sed -i 's|SystemdCgroup = false|SystemdCgroup = true|' /etc/containerd/config.toml

# Systemd override to force config usage
sudo mkdir -p /etc/systemd/system/containerd.service.d
cat <<'EOF' | sudo tee /etc/systemd/system/containerd.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/containerd -c /etc/containerd/config.toml
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl restart containerd

echo "[Step 8] Configure crictl..."
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo crictl info

echo "[Step 9] Configure firewall..."
systemctl stop firewalld
systemctl disable firewalld

echo "[Step 10] Reset previous kube state..."
sudo kubeadm reset -f || true
sudo rm -rf /etc/cni/net.d/* || true

echo "[Step 11] Initialize Kubernetes cluster..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

echo "[Step 12] Configure kubectl..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id -u)":"$(id -g)" $HOME/.kube/config

echo "[Step 13] Deploy Flannel CNI..."
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "[Step 14] Verify cluster..."
kubectl get nodes
kubectl get pods -n kube-flannel -o wide
kubectl get pods -A
setenforce 0

echo "✅ Kubernetes setup completed successfully!"
