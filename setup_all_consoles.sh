#!/bin/sh
# --- CONFIGURATION ---
BASE_PORT=2001
LOG_FILE="/tmp/vm_serial_map.txt"

echo "=== VM Serial Console Audit Started: $(date) ===" | tee $LOG_FILE

# Get only the IDs of the VMs
IDS=$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print $1}')

for VMID in $IDS; do
    # Get the Name
    VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
    
    # Manually find the VMX path by searching the volumes for the VM name
    VMX_PATH=$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
    
    if [ -f "$VMX_PATH" ]; then
        # Check if serial0 is already there
        HAS_SERIAL=$(grep -i "serial0.present" "$VMX_PATH" | grep -i "TRUE")

        if [ -z "$HAS_SERIAL" ]; then
            echo "[NEW/MISSING] $VMNAME (ID: $VMID). Configuring..." | tee -a $LOG_FILE
            
            # Power off
            STATE=$(vim-cmd vmsvc/power.getstate $VMID | grep "on")
            if [ -n "$STATE" ]; then
                echo "  -> Powering off..."
                vim-cmd vmsvc/power.off $VMID > /dev/null
                sleep 3
            fi

            VM_PORT=$((BASE_PORT + VMID))
            
            echo "  -> Injecting Serial Config (Port $VM_PORT)..."
            # Append configuration
            printf "serial0.present = \"TRUE\"\nserial0.yieldOnPoll = \"TRUE\"\nserial0.fileType = \"network\"\nserial0.fileName = \"telnet://:$VM_PORT\"\nserial0.network.endPoint = \"server\"\n" >> "$VMX_PATH"
            
            # Reload VM registration
            vim-cmd vmsvc/reload $VMID
            
            echo "  -> Powering VM back on..."
            vim-cmd vmsvc/power.on $VMID > /dev/null
            echo "  -> SUCCESS: $VMNAME on Port $VM_PORT" | tee -a $LOG_FILE
        else
            echo "[READY] $VMNAME already configured." | tee -a $LOG_FILE
        fi
    else
        echo "[ERROR] Could not find VMX file for $VMNAME" | tee -a $LOG_FILE
    fi
done

echo "=== Setup Complete ==="
