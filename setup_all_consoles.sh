#!/bin/sh
# --- CONFIGURATION ---
BASE_PORT=2001
LOG_FILE="/tmp/vm_serial_map.txt"

echo "=== VM Serial Console Audit Started: $(date) ===" | tee $LOG_FILE

# Get all VM IDs
VMLIST=$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print $1}')

for VMID in $VMLIST; do
    VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
    
    # Check if VM already has a serial port
    HAS_SERIAL=$(vim-cmd vmsvc/device.getdevices $VMID | grep -i "serial")

    if [ -z "$HAS_SERIAL" ]; then
        echo "[NEW/MISSING] $VMNAME (ID: $VMID) needs configuration." | tee -a $LOG_FILE
        
        # Check power state
        STATE=$(vim-cmd vmsvc/power.getstate $VMID | grep "Powered on")
        if [ -n "$STATE" ]; then
            echo "  -> Powering off VM..."
            vim-cmd vmsvc/power.off $VMID > /dev/null
            sleep 5
        fi

        # Assign a port based on VMID to ensure it is unique
        VM_PORT=$((BASE_PORT + VMID))
        
        echo "  -> Adding Serial Port on Port: $VM_PORT" | tee -a $LOG_FILE
        vim-cmd vmsvc/device.conn.add $VMID serial0 network server telnet://:$VM_PORT > /dev/null
        
        # Turn it back on
        echo "  -> Powering VM back on..."
        vim-cmd vmsvc/power.on $VMID > /dev/null
    else
        # Extract the existing port if possible for the log
        echo "[READY] $VMNAME already has a serial port." | tee -a $LOG_FILE
    fi
done

echo "=== Setup Complete. Check $LOG_FILE for your PuTTY port numbers ==="
