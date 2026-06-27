#!/bin/bash

# ==========================================================
# NETBOX DEVICE MONITOR
# TASK 1
# ==========================================================

NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"

SSH_USER="root"
SSH_PASS="Root@123"

# ----------------------------------------------------------
# Dependency Check
# ----------------------------------------------------------

for cmd in curl jq sshpass ping
do
    command -v $cmd >/dev/null 2>&1 || {
        echo "$cmd not installed"
        exit 1
    }
done

# ----------------------------------------------------------
# Get Devices from NetBox
# ----------------------------------------------------------

echo ""
echo "Connecting to NetBox..."

DEVICES=$(curl -sk \
-H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/dcim/devices/?limit=1000")

COUNT=$(echo "$DEVICES" | jq '.count')

echo ""
echo "Total Devices Found : $COUNT"
echo ""

while read -r DEVICE
do
echo ""
echo "******** NEW DEVICE ********"

    DEVICE_ID=$(echo "$DEVICE" | jq -r '.id')
    HOSTNAME=$(echo "$DEVICE" | jq -r '.name')
    STATUS=$(echo "$DEVICE" | jq -r '.status.value')
    PRIMARY_IP=$(echo "$DEVICE" | jq -r '.primary_ip4.address // "NO-IP"')
    
	HOST=$(echo "$PRIMARY_IP" | cut -d/ -f1)
	
    echo "----------------------------------------"
    echo "Device ID : $DEVICE_ID"
    echo "Hostname  : $HOSTNAME"
    echo "Status    : $STATUS"
    echo "PrimaryIP : $PRIMARY_IP"
    echo "----------------------------------------"

# ----------------------------------------------------------
# Existing Cluster Information
# ----------------------------------------------------------

CLUSTER_ID=$(echo "$DEVICE" | jq -r '.cluster.id // empty')
CLUSTER_NAME=$(echo "$DEVICE" | jq -r '.cluster.name // empty')

if [ -n "$CLUSTER_ID" ]; then

    CLUSTER_INFO=$(curl -sk \
    -H "Authorization: Token $NETBOX_TOKEN" \
    "$NETBOX_URL/virtualization/clusters/$CLUSTER_ID/")

    CLUSTER_TYPE=$(echo "$CLUSTER_INFO" | jq -r '.type.name // empty')
    CLUSTER_GROUP=$(echo "$CLUSTER_INFO" | jq -r '.group.name // empty')

else

    CLUSTER_TYPE="N/A"
    CLUSTER_GROUP="N/A"

fi

# ----------------------------------------------------------
# STAGED DEVICE CHECK
# ----------------------------------------------------------

if [ "$STATUS" = "staged" ]
then

    echo ""
    echo "STAGED DEVICE DETECTED : $HOSTNAME"

    if [ -z "$HOST" ] || [ "$HOST" = "NO-IP" ]
    then
        echo "No Primary IP found"
        continue
    fi

    echo "Pinging $HOST ..."

    if ping -c1 -W2 "$HOST" >/dev/null 2>&1
    then

        echo "Host reachable"

        echo "Updating status to ACTIVE..."

        curl -sk -X PATCH \
        "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
              "status":"active"
            }' >/dev/null

        STATUS="active"

        echo "Device promoted to ACTIVE"

    else

        echo "Host unreachable"

        echo "Leaving device in STAGED state"

        continue

    fi

fi

# ----------------------------------------------------------
# ACTIVE DEVICE INVENTORY COLLECTION
# ----------------------------------------------------------

if [ "$STATUS" != "active" ]
then
    continue
fi

echo ""
echo "Collecting inventory from $HOSTNAME ..."

if ! sshpass -p "$SSH_PASS" \
ssh -n \
-o ConnectTimeout=5 \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} "echo ok" >/dev/null 2>&1
then

    echo "SSH Failed - Skipping"

    continue

fi

CURRENT_HOSTNAME=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} hostname 2>/dev/null)

CURRENT_KERNEL=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} "uname -r" 2>/dev/null)

OS_RELEASE=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} "cat /etc/redhat-release" 2>/dev/null)

CPU_COUNT=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} "nproc" 2>/dev/null)

RAM_GB=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} \
"awk '/MemTotal/ {printf \"%d\", (\$2/1024/1024)+0.5}' /proc/meminfo")

DISK_SIZE=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} \
"lsblk -bdno SIZE | awk '{s+=\$1} END {printf \"%.0f GB\",s/1024/1024/1024}'")

VM_TYPE=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} \
"systemd-detect-virt" 2>/dev/null)

[ -z "$VM_TYPE" ] && VM_TYPE="Physical"


IFACE_DATA=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} \
"ip -o -4 addr show scope global | head -1")

IFACE=$(echo "$IFACE_DATA" | awk '{print $2}')

IPADDR=$(echo "$IFACE_DATA" | awk '{print $4}')

MAC=$(sshpass -p "$SSH_PASS" ssh -n \
-o StrictHostKeyChecking=no \
${SSH_USER}@${HOST} \
"cat /sys/class/net/$IFACE/address" 2>/dev/null | \
tr '[:lower:]' '[:upper:]')


echo "Hostname : $CURRENT_HOSTNAME"
echo "Kernel   : $CURRENT_KERNEL"
echo "OS       : $OS_RELEASE"
echo "CPU      : $CPU_COUNT"
echo "RAM      : $RAM_GB GB"
echo "Disk     : $DISK_SIZE"
echo "VM Type  : $VM_TYPE"
echo "Interface: $IFACE"
echo "IP       : $IPADDR"
echo "MAC      : $MAC"
echo ""

# ----------------------------------------------------------
# Kernel Compliance
# ----------------------------------------------------------

if echo "$OS_RELEASE" | grep -q "release 7"
then
    EXPECTED_KERNEL="3.10.0-1160.119.1.el7.x86_64"

elif echo "$OS_RELEASE" | grep -q "release 8"
then
    EXPECTED_KERNEL="4.18.0-553.134.1.el8_10.x86_64"

else
    EXPECTED_KERNEL="Unknown"
fi

if [ "$CURRENT_KERNEL" = "$EXPECTED_KERNEL" ]
then
    PATCH_STATUS="Compliant"
else
    PATCH_STATUS="Non-Compliant"
fi

LAST_PATCH_CHECK=$(date +%F)

echo "Expected Kernel : $EXPECTED_KERNEL"
echo "Patch Status    : $PATCH_STATUS"
echo ""

# ----------------------------------------------------------
# INTERFACE SYNC
# ----------------------------------------------------------

echo "Checking NetBox Interface..."

NB_IFACE=$(curl -sk \
-H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID&limit=1" |
jq -r '.results[0].name')

NB_IFACE_ID=$(curl -sk \
-H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID&limit=1" |
jq -r '.results[0].id')

NB_MAC=$(curl -sk \
-H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID&limit=1" |
jq -r '.results[0].mac_address // empty')

echo "NetBox Interface : $NB_IFACE"
echo "NetBox MAC       : $NB_MAC"

echo "Linux Interface  : $IFACE"
echo "Linux MAC        : $MAC"

if [ "$NB_IFACE" != "$IFACE" ]
then

    echo "Updating Interface Name..."

    curl -sk -X PATCH \
    "$NETBOX_URL/dcim/interfaces/$NB_IFACE_ID/" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\":\"$IFACE\"
    }" >/dev/null

    echo "Interface Updated"
fi

# ----------------------------------------------------------
# Update MAC Address
# ----------------------------------------------------------

if [ "$NB_MAC" != "$MAC" ]
then
    echo "Updating MAC Address..."

    curl -sk -X PATCH \
    "$NETBOX_URL/dcim/interfaces/$NB_IFACE_ID/" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"mac_address\": \"$MAC\"
    }" >/dev/null

    echo "MAC Address Updated"
fi

# ----------------------------------------------------------
# Update Custom Fields
# ----------------------------------------------------------

curl -sk -X PATCH \
"$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
-H "Authorization: Token $NETBOX_TOKEN" \
-H "Content-Type: application/json" \
-d "{
  \"custom_fields\": {
    \"cpu_count\": $CPU_COUNT,
    \"ram_gb\": $RAM_GB,
    \"disk_gb\": \"$DISK_SIZE\",
    \"vm_type\": \"$VM_TYPE\",
    \"kernel\": \"$CURRENT_KERNEL\",
    \"expected_kernel\": \"$EXPECTED_KERNEL\",
    \"patch_status\": \"$PATCH_STATUS\",
    \"last_patch_check\": \"$LAST_PATCH_CHECK\"
  }
}" >/dev/null

echo "NetBox Custom Fields Updated"

# ----------------------------------------------------------
# Update Device Name if Hostname Changed
# ----------------------------------------------------------

if [ "$HOSTNAME" != "$CURRENT_HOSTNAME" ]
then

    echo "Hostname mismatch detected"

    curl -sk -X PATCH \
    "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
          \"name\":\"$CURRENT_HOSTNAME\"
        }" >/dev/null

    echo "Hostname updated in NetBox"

fi

echo "Finished processing $HOSTNAME"
echo "======================================="

echo "******** DEVICE COMPLETE ********"
echo ""

done < <(
    echo "$DEVICES" | jq -c '.results[]'
)

