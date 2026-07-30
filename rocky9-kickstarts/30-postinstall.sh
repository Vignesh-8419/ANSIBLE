#!/bin/bash
#==============================================================================
# 30-postinstall.sh
#
# Rocky Linux 9 Golden Image
# Initial System Hardening & Base Configuration Tuning
#==============================================================================

set -euo pipefail

LOG=/root/30-postinstall.log
exec > >(tee -a "$LOG") 2>&1

echo
echo "========================================================"
echo "Rocky 9 Golden Image - Post Installation Base Optimization"
echo "========================================================"

###############################################################################
# Timezone Alignment
###############################################################################
echo "Configuring system timezone..."
timedatectl set-timezone Asia/Kolkata || true

###############################################################################
# Enable Core System Services
###############################################################################
SERVICES=(
    NetworkManager
    sshd
    chronyd
    firewalld
    fstrim.timer
)

for svc in "${SERVICES[@]}"
do
    if systemctl list-unit-files | grep -q "^${svc}"; then
        echo "Enabling service daemon: ${svc}"
        systemctl enable "$svc" || true
    fi
done

if systemctl list-unit-files | grep -q "^vmtoolsd"; then
    echo "Enabling virtualization guest agent: vmtoolsd"
    systemctl enable vmtoolsd || true
fi

###############################################################################
# Secure SSH Configuration
###############################################################################
SSHDCFG=/etc/ssh/sshd_config
if [ -f "$SSHDCFG" ]; then
    echo "Hardening SSH configuration..."
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$SSHDCFG"
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHDCFG"
    sed -i 's/^#\?UseDNS.*/UseDNS no/' "$SSHDCFG"
fi

###############################################################################
# SELinux Policy Enforcement
###############################################################################
if [ -f /etc/selinux/config ]; then
    echo "Configuring SELinux policy baseline..."
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi
setenforce 1 || true

###############################################################################
# Firewall Base Configuration
###############################################################################
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "Configuring firewalld permanent rules matrix..."
    firewall-cmd --permanent --add-service=ssh || true
    firewall-cmd --reload || true
fi

###############################################################################
# DNF Performance Multiplier Configuration
###############################################################################
echo "Optimizing DNF package management engine parameters..."
cat >/etc/dnf/dnf.conf <<EOF
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=True
skip_if_unavailable=False
fastestmirror=True
max_parallel_downloads=10
EOF

###############################################################################
# Sysctl Micro-Kernel Tuning
###############################################################################
echo "Applying low-latency kernel runtime tuning configurations..."
cat >/etc/sysctl.d/99-golden.conf <<EOF
vm.swappiness=10
net.ipv4.ip_forward=0
kernel.sysrq=0
EOF

sysctl --system || true

###############################################################################
# Disable Ctrl-Alt-Del Interactive Traps
###############################################################################
echo "Masking interactive terminal intercept signals..."
systemctl mask ctrl-alt-del.target || true

###############################################################################
# Message of the Day (MOTD) Setup
###############################################################################
echo "Deploying login profile banners..."
cat >/etc/motd <<EOF

==================================================
 Rocky Linux 9 Enterprise Golden Image
 UEFI + GPT + RAID1 + LVM
==================================================

EOF

###############################################################################
# Shell Execution History Tuning
###############################################################################
echo "Configuring environment operational audit trails..."
cat >/etc/profile.d/history.sh <<EOF
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups
EOF

chmod 644 /etc/profile.d/history.sh

###############################################################################
# Root Vim Environment Configuration
###############################################################################
echo "Applying administrative text editor environment configurations..."
cat >/root/.vimrc <<EOF
set number
syntax on
set background=dark
EOF

###############################################################################
# Sync Disks & Close Base Stage
###############################################################################
sync

###############################################################################
# Helper to mount EFI manually when required (Rocky 9 Path Adapted)
###############################################################################
cat >/usr/local/sbin/mount-efi <<'EOF'
#!/bin/bash
set -euo pipefail

mkdir -p /boot/efi

# Already mounted
mountpoint -q /boot/efi && exit 0

while read -r dev
do
    if mount "$dev" /boot/efi 2>/dev/null; then
        # Unified tracking: check fallback paths which Rocky 9 maps natively
        if [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ] || \
           [ -f /boot/efi/EFI/rocky/shimx64.efi ]; then
            echo "Mounted EFI partition: $dev"
            exit 0
        fi
        umount /boot/efi
    fi
done < <(blkid -t TYPE=vfat -o device)

echo "No valid EFI partition found."
exit 1
EOF

chmod 755 /usr/local/sbin/mount-efi

echo
echo "========================================================"
echo "30-postinstall.sh completed successfully"
echo "========================================================"
