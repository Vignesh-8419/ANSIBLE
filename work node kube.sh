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
sudo firewall-cmd --permanent --add-port=10250/tcp || true
sudo firewall-cmd --reload || true

echo "[Step 10] Reset previous kube state..."
sudo kubeadm reset -f || true
sudo rm -rf /etc/cni/net.d/* || true
# Stop kubelet
systemctl stop kubelet

# Remove old CNI bridge
ip link delete cni0 || true

# Clean CNI state
rm -rf /var/lib/cni/*
rm -rf /etc/cni/net.d/*

# Restart kubelet
systemctl start kubelet
#on control node kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

kubectl delete pod -n kube-flannel -l app=flannel
# Bring the interface down
ip link set cni0 down

# Delete the bridge and the flannel interface
brctl delbr cni0 || ip link delete cni0
ip link delete flannel.1

# Delete the local flannel subnet file to let it recreate
rm -rf /var/lib/cni/flannel/*
rm -rf /var/lib/cni/networks/cni0/*


sudo dnf install -y containernetworking-plugins
ls /opt/cni/bin
sudo mkdir -p /etc/cni/net.d
# 1. Disable firewalld temporarily to see if it's the culprit
systemctl stop firewalld
systemctl disable firewalld

# 2. Ensure IP forwarding is enabled (Crucial for Kubernetes)
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.ipv4.ip_forward=1

# 3. Restart the container runtime and kubelet to pick up changes
systemctl restart containerd
systemctl restart kubelet

echo "[Step 11] Join Kubernetes cluster..."
# ⚠️ Replace the line below with the actual join command from your control plane:
# Run on control plane: kubeadm token create --print-join-command
# Example:
# sudo kubeadm join <CONTROL_PLANE_IP>:6443 --token <TOKEN> \
#     --discovery-token-ca-cert-hash sha256:<HASH>
echo "👉 Please paste your kubeadm join command here"
