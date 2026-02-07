#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
MY_NAME="dns-server-01"
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

echo "=========================================================="
echo "STEP 1: FETCHING LIVE IPs & CONFIGURING ESXi HARDWARE"
echo "=========================================================="

# Download the GRUB script locally for distribution
wget -q "$GITHUB_URL" -O enable-verbose-boot.sh || true
chmod +x enable-verbose-boot.sh

# Fetch VM list and discover IPs via ESXi ARP table/Neighbor list
# This creates a list format: VMNAME|IP
VM_DATA=$(sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP << EOF
    # Get all VM IDs and Names
    IDS=\$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print \$1}')
    
    for VMID in \$IDS; do
        VMNAME=\$(vim-cmd vmsvc/getallvms | awk -v id="\$VMID" '\$1==id {print \$2}')
        
        # Skip DNS server
        if [ "\$VMNAME" == "$MY_NAME" ]; then continue; fi

        # Find VMX and Check Hardware
        VMX_PATH=\$(find /vmfs/volumes/ -name "\${VMNAME}.vmx" | head -n 1)
        if [ -f "\$VMX_PATH" ] && ! grep -q "serial0.present" "\$VMX_PATH"; then
            echo "CONFIG_HW|\$VMNAME|\$VMID"
            # Power off and configure if hardware is missing
            [ -n "\$(vim-cmd vmsvc/power.getstate \$VMID | grep on)" ] && vim-cmd vmsvc/power.off \$VMID > /dev/null && sleep 3
            VM_PORT=\$((2000 + \$VMID))
            printf "serial0.present = \"TRUE\"\nserial0.yieldOnPoll = \"TRUE\"\nserial0.fileType = \"network\"\nserial0.fileName = \"telnet://:\$VM_PORT\"\nserial0.network.endPoint = \"server\"\n" >> "\$VMX_PATH"
            vim-cmd vmsvc/reload \$VMID
            vim-cmd vmsvc/power.on \$VMID > /dev/null
        fi

        # Attempt to find the IP of the VM using ARP/Neighbor cache
        # This matches the MAC of the VM to an IP ESXi has seen
        VM_MAC=\$(grep -i "ethernet0.generatedAddress" "\$VMX_PATH" | cut -d "\"" -f2)
        VM_IP=\$(esxcli network ip neighbor list | grep -i "\$VM_MAC" | awk '{print \$1}' | head -n 1)
        
        if [ -n "\$VM_IP" ]; then
            echo "GUEST_DATA|\$VMNAME|\$VM_IP"
        fi
    done
EOF
)

echo "=========================================================="
echo "STEP 2: SMART GUEST OS UPDATE (SKIP IF ALREADY DONE)"
echo "=========================================================="

for line in $VM_DATA; do
    if [[ $line == GUEST_DATA* ]]; then
        VMNAME=$(echo $line | cut -d'|' -f2)
        VMIP=$(echo $line | cut -d'|' -f3)

        echo "Checking $VMNAME ($VMIP)..."

        # Check if console is already configured inside the VM
        ALREADY_DONE=$(sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" "grep 'console=ttyS0' /etc/default/grub" 2>/dev/null)

        if [ -z "$ALREADY_DONE" ]; then
            echo "  -> Configuration missing. Updating and Rebooting..."
            sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no enable-verbose-boot.sh root@"$VMIP":/tmp/ >/dev/null 2>&1
            sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" \
            "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
        else
            echo "  -> [OK] Already configured. Skipping reboot."
        fi
    fi
done

wait
echo "=========================================================="
echo "ALL TASKS COMPLETE"
echo "=========================================================="
