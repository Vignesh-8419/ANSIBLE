#!/bin/bash

# --- 1. Define Variables ---
NAMESPACE="awx"
VIP="192.168.253.145"
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

echo "🧹 Starting Clean Uninstallation..."

# --- 2. Remove AWX Resources ---
echo "🗑️ Removing AWX Instance and Ingress..."
kubectl delete awx awx-server -n $NAMESPACE --timeout=60s || echo "AWX instance already gone."
kubectl delete ingress awx-ingress -n $NAMESPACE --ignore-not-found

# --- 3. Uninstall AWX Operator ---
if [ -d "awx-operator" ]; then
    echo "🏗️ Uninstalling AWX Operator via Makefile..."
    cd awx-operator
    make undeploy NAMESPACE=$NAMESPACE || true
    cd ..
    rm -rf awx-operator
fi

# --- 4. Cleanup Namespace & Secrets ---
echo "🧨 Deleting Namespace $NAMESPACE..."
kubectl delete namespace $NAMESPACE --ignore-not-found

# --- 5. Uninstall K3s Cluster ---
echo "☸️ Uninstalling K3s..."
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    /usr/local/bin/k3s-uninstall.sh
else
    echo "K3s uninstall script not found. Manual cleanup required."
fi

# --- 6. Wipe Persistent Data ---
echo "💾 Wiping local-path storage and configurations..."
rm -rf /var/lib/rancher/k3s
rm -rf /etc/rancher/k3s
rm -rf $HOME/.kube
rm -rf /var/lib/kubelet

# --- 7. Remove Virtual IP ---
echo "🌐 Removing Virtual IP $VIP from $INTERFACE..."
ip addr del $VIP/24 dev $INTERFACE 2>/dev/null || true

# --- 8. Reset SELinux & Firewall (Optional) ---
echo "🔒 Resetting security defaults..."
# setenforce 1  # Uncomment if you want to re-enable SELinux enforcement
# systemctl start firewalld # Uncomment if you want to restart firewall

echo "-------------------------------------------------------"
echo "✅ CLEANUP COMPLETE!"
echo "Your server is now back to its original state."
echo "-------------------------------------------------------"
