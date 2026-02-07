#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
IP_LIST="ips.txt"
MY_NAME="dns-server-01"
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

echo "=========================================================="
echo "STEP 1: CONFIGURING ESXi HARDWARE (VIA REMOTE SSH)"
echo "=========================================================="

# We push your working hardware logic to the ESXi host
sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP << EOF
    BASE_PORT=2001
    IDS=\$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print \$1}')

    for VMID in \$IDS; do
        VMNAME=\$(vim-cmd vmsvc/getallvms | awk -v id="\$VMID" '\$1==id {print \$2}')
        
        # Skip dns-server-01 inside ESXi logic
        if [ "\$VMNAME" == "$MY_NAME" ]; then
            continue
        fi

        VMX_PATH=\$(find /vmfs/volumes/ -name "\${VMNAME}.vmx" | head -n 1)
        
        if [ -f "\$VMX_PATH" ]; then
            HAS_SERIAL=\$(grep -i "serial0.present" "\$VMX_PATH" | grep -i "TRUE")

            if [ -z "\$HAS_SERIAL" ]; then
                echo "Configuring Hardware for \$VMNAME (ID: \$VMID)..."
                
                # Power off if needed
                STATE=\$(vim-cmd vmsvc/power.getstate \$VMID | grep "on")
                if [ -n "\$STATE" ]; then
                    vim-cmd vmsvc/power.off \$VMID > /dev/null
                    sleep 3
                fi

                VM_PORT=\$((BASE_PORT + VMID))
                printf "serial0.present = \"TRUE\"\nserial0.yieldOnPoll = \"TRUE\"\nserial0.fileType = \"network\"\nserial0.fileName = \"telnet://:\$VM_PORT\"\nserial0.network.endPoint = \"server\"\n" >> "\$VMX_PATH"
                
                vim-cmd vmsvc/reload \$VMID
                vim-cmd vmsvc/power.on \$VMID > /dev/null
                echo "  -> SUCCESS: \$VMNAME on Port \$VM_PORT"
            else
                echo "\$VMNAME already has hardware configured."
            fi
        fi
    done
    # Ensure Firewall is open
    esxcli network firewall ruleset set -e true -r vSPC 2>/dev/null || esxcli network firewall ruleset set -e true -r vmSerialPortOnNetwork
EOF

echo ""
echo "=========================================================="
echo "STEP 2: CONFIGURING GUEST OS (VIA GITHUB & SSHPASS)"
echo "=========================================================="

# Download your script from GitHub locally
wget -q "$GITHUB_URL" -O enable-verbose-boot.sh || true
chmod +x enable-verbose-boot.sh

if [ ! -f "$IP_LIST" ]; then
    echo "Error: $IP_LIST not found. Create it with VM IPs to complete Step 2."
    exit 1
fi

for ip in $(cat "$IP_LIST"); do
    # Just in case your IP list includes the DNS server IP
    # If you know the DNS server IP, you can add an extra check here
    
    echo "Processing VM IP: $ip..."
    
    # 1. Copy script to VM
    sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no enable-verbose-boot.sh root@"$ip":/tmp/ >/dev/null 2>&1
    
    # 2. Execute and Reboot in background
    sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$ip" \
    "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
done

wait
echo "=========================================================="
echo "ALL SYSTEMS UPDATED AND REBOOTING"
echo "=========================================================="
