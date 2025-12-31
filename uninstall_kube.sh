#!/bin/bash
# ============================================
# Full Kubernetes + AWX + Longhorn Uninstall Script
# ============================================

CONTROL_NODE="awx-control-node-01.vgs.com"
WORK_NODES=("awx-work-node-01.vgs.com" "awx-work-node-02.vgs.com")
SSH_PASS="Root@123"  # Replace with your root password

# -----------------------------
# Function to run command over sshpass
# -----------------------------
run_ssh() {
    local NODE=$1
    local CMD=$2
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no root@$NODE "$CMD"
}

# -----------------------------
# Cleanup function for any node
# -----------------------------
cleanup_node() {
    echo "Cleaning $1 ..."
    run_ssh $1 "
        echo 'Stopping services...';
        systemctl stop kubelet containerd docker || true;

        echo 'Resetting kubeadm...';
        kubeadm reset -f || true;

        echo 'Removing Kubernetes packages...';
        yum remove -y kubeadm kubelet kubectl kubernetes-cni containerd docker || true;

        echo 'Deleting configuration and data...';
        rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube /etc/cni/net.d /opt/cni/bin /var/lib/containerd /var/lib/docker;

        echo 'Flushing iptables...';
        iptables -F; iptables -X; iptables -t nat -F; iptables -t nat -X; iptables -t mangle -F; iptables -t mangle -X;

        echo 'Reloading systemd...';
        systemctl daemon-reload;
        systemctl reset-failed;
    "
}

# -----------------------------
# Step 1: Clean control-plane node
# -----------------------------
cleanup_node $CONTROL_NODE

# -----------------------------
# Step 2: Clean all worker nodes
# -----------------------------
for node in "${WORK_NODES[@]}"; do
    cleanup_node $node
done

echo "Uninstallation complete! All Kubernetes, AWX, Longhorn, and container runtimes removed."
