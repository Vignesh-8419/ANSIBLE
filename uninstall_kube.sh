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
        systemctl stop kubelet || true;

        # 1. FORCE KILL existing K8s processes (Prevents port 6443 staying open)
        echo 'Killing orphan processes...';
        killall -9 kube-apiserver kube-controller-manager kube-scheduler kube-proxy etcd containerd-shim 2>/dev/null || true;
        lsof -t -i:6443 | xargs kill -9 2>/dev/null || true;

        echo 'Resetting kubeadm...';
        kubeadm reset -f || true;

        # 2. UNMOUNT lingering filesystems (Prevents directory deletion errors)
        echo 'Clearing mounts...';
        for m in \$(mount | grep /var/lib/kubelet | awk '{print \$3}'); do umount -l \$m; done

        echo 'Removing Kubernetes packages...';
        systemctl stop containerd docker 2>/dev/null || true;
        yum remove -y kubeadm kubelet kubectl kubernetes-cni containerd.io docker-ce docker-ce-cli 2>/dev/null || true;

        echo 'Deleting configuration and data...';
        rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube /etc/cni/net.d /opt/cni/bin /var/lib/containerd /var/lib/docker /var/run/kubernetes;
        
        # 3. CLEAN IPVS/IPTABLES (Prevents networking conflicts on reinstall)
        echo 'Flushing network rules...';
        iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X;
        ipvsadm --clear 2>/dev/null || true;
        ip link delete cni0 2>/dev/null || true;
        ip link delete flannel.1 2>/dev/null || true;

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
