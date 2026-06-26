#!/bin/bash
#===============================================================================
# Ansible Server (AWX + K3s) Kernel Tuning
#===============================================================================

set -e

echo "Applying kernel tuning..."

cat >/etc/sysctl.d/99-awx.conf <<'EOF'
###############################################################################
# Memory
###############################################################################

# Avoid swapping unless necessary
vm.swappiness = 30

# Keep filesystem cache longer
vm.vfs_cache_pressure = 50

# Kubernetes/PostgreSQL recommendation
vm.overcommit_memory = 1

# Flush dirty pages earlier
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

###############################################################################
# File Descriptors
###############################################################################

fs.file-max = 2097152

###############################################################################
# Inotify (AWX/Kubernetes)
###############################################################################

fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024

###############################################################################
# Network
###############################################################################

net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096

###############################################################################
# TCP
###############################################################################

net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_tw_reuse = 1

###############################################################################
# Virtual Memory
###############################################################################

vm.max_map_count = 262144
EOF

echo "Applying sysctl configuration..."
sysctl --system

echo
echo "Checking Transparent Huge Pages..."

if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag

    cat >/etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable disable-thp.service
    systemctl start disable-thp.service
fi

echo
echo "=============================="
echo "Applied Kernel Parameters"
echo "=============================="

sysctl vm.swappiness
sysctl vm.vfs_cache_pressure
sysctl vm.overcommit_memory
sysctl vm.dirty_background_ratio
sysctl vm.dirty_ratio
sysctl fs.file-max
sysctl fs.inotify.max_user_watches
sysctl fs.inotify.max_user_instances
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_max_syn_backlog
sysctl vm.max_map_count

echo
echo "Transparent Huge Pages:"
cat /sys/kernel/mm/transparent_hugepage/enabled

echo
echo "Kernel tuning completed successfully."
