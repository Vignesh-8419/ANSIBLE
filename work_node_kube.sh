#!/bin/bash
set -euo pipefail

echo "[Step 1] Disable swap..."
sudo sed -i '/\sswap\s/d' /etc/fstab
sudo swapoff -a

echo "[Step 2] Enable kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

echo "[Step 3] Set sysctl params..."
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
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
sudo systemctl enable kubelet

echo "[Step 6] Remove conflicting runc..."
sudo dnf remove -y runc || true

echo "[Step 7] Install containerd.io..."
sudo dnf -y install 'dnf-command(config-manager)' || true
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io iproute-tc

echo "[Step 8] Configure containerd..."
sudo mkdir -p /etc/containerd
# Generate default config
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# 1. Update the sandbox image
sudo sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml

# 2. Fix SystemdCgroup (This is the cleaner way to do it)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Systemd override to force config path
sudo mkdir -p /etc/systemd/system/containerd.service.d
cat <<'EOF' | sudo tee /etc/systemd/system/containerd.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/containerd -c /etc/containerd/config.toml
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now containerd

echo "[Step 9] Configure crictl..."
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "[Step 10] SELinux and firewall..."
sudo setenforce 0 || true
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config || true
sudo systemctl stop firewalld || true
sudo systemctl disable firewalld || true

echo "[Step 11] Reset kube state..."
sudo kubeadm reset -f || true
sudo rm -rf /etc/cni/net.d/* /var/lib/cni/* || true
sudo systemctl restart containerd
sudo systemctl restart kubelet

echo "[Step 12] Install CNI plugins..."
sudo dnf install -y containernetworking-plugins
ls /opt/cni/bin || true

echo "[Step 13] Ready to join cluster..."
echo "👉 Run the kubeadm join command from your control plane here."

