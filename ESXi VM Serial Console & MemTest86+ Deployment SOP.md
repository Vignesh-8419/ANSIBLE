ESXi VM Serial Console & MemTest86+ Deployment SOP
Overview
This automation audits VMware ESXi VMs, enables serial console access, deploys MemTest86+, updates GRUB configuration, and validates guest accessibility.
Prerequisites
```bash
dnf install -y sshpass
```
Execute
```bash
chmod +x vm-audit-memtest.sh
./vm-audit-memtest.sh
```
Complete Automation Script
```bash
#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
MY_HOSTNAME=$(hostname)

# SSH OPTIONS to ignore host key changes
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET"

# --- STEP 0: FETCH ALL VMs FROM ESXI ---
echo "[*] Fetching ALL VMs from ESXi ($ESXI_IP)..."
VMLIST=$(sshpass -p "$ESXI_PASS" ssh $SSH_OPTS root@$ESXI_IP "vim-cmd vmsvc/getallvms" | awk 'NR>1 {print $2}')

if [ -z "$VMLIST" ]; then
    echo "[!] No VMs found on ESXi. Exiting."
    exit 1
fi

# --- GENERATE THE LOCAL GRUB SCRIPT ---
cat << 'EOF' > enable-verbose-boot.sh
#!/bin/bash
mkdir -p /boot/efi/EFI/memtest
curl -L -f -o /boot/efi/EFI/memtest/memtest.efi https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus || exit 1
chmod 755 /boot/efi/EFI/memtest/memtest.efi
EOF

chmod +x enable-verbose-boot.sh

# --- MAIN LOOP ---
for VMNAME in $VMLIST; do
    echo "=========================================================="
    read -p "Begin Audit for $VMNAME? (y/n): " CONFIRM
done

echo "AUDIT SEQUENCE COMPLETE"

```
