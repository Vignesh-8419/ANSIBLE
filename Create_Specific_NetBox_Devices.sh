#!/bin/bash
set -euo pipefail

# ============================================================
# NETBOX SPECIFIC DEVICE CREATION TOOL
# ============================================================

# ---------------- CONFIG ----------------

NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"

SSH_USER="admin"
SSH_PASS='Vigneshv12$'

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

# ---------------- COLORS ----------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ---------------- GLOBALS ----------------

SUCCESS_LIST=""
FAILED_LIST=""

# ============================================================
# UI
# ============================================================

banner() {
    clear

    echo
    echo "============================================================"
    echo "        NETBOX SPECIFIC DEVICE CREATION TOOL"
    echo "============================================================"
    echo
}

header() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

error() {
    echo -e "${RED}$1${NC}"
}

success() {
    echo -e "${GREEN}$1${NC}"
}

info() {
    echo -e "${CYAN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# ============================================================
# DEPENDENCY CHECK
# ============================================================

check_dependencies() {

    echo "Checking dependencies..."

    for cmd in curl jq ssh sshpass ping
    do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Missing dependency: $cmd"
            exit 1
        fi
    done

    success "Dependencies OK"
}

# ============================================================
# NETBOX API
# ============================================================

api_get() {

    local endpoint="$1"

    curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/$endpoint"
}

api_post() {

    local endpoint="$1"
    local payload="$2"

    curl -sk \
        -X POST \
        "$NETBOX_URL/$endpoint" \
        -H "Content-Type: application/json" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        --data "$payload"
}

api_patch() {

    local endpoint="$1"
    local payload="$2"

    curl -sk \
        -X PATCH \
        "$NETBOX_URL/$endpoint" \
        -H "Content-Type: application/json" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        --data "$payload"
}

# ============================================================
# CHECK NETBOX
# ============================================================

check_netbox() {

    echo
    echo "Checking NetBox API..."

    local code

    code=$(curl -sk \
        -o /dev/null \
        -w "%{http_code}" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/status/")

    if [ "$code" != "200" ]; then
        error "NetBox API check failed. HTTP Code: $code"
        exit 1
    fi

    success "NetBox API reachable"
}

# ============================================================
# SLUGIFY
# ============================================================

slugify() {

    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr ' ' '-' |
        sed 's/[^a-z0-9-]//g'
}

# ============================================================
# URL ENCODE
# ============================================================

urlencode() {

    jq -rn --arg value "$1" '$value | @uri'
}

# ============================================================
# GET OR CREATE CLUSTER TYPE
# ============================================================

get_or_create_cluster_type() {

    local name="$1"
    local slug

    slug=$(slugify "$name")

    local response
    local id

    response=$(api_get \
        "virtualization/cluster-types/?name=$(urlencode "$name")")

    id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$id" ]; then
        echo "$id"
        return
    fi

    response=$(api_post \
        "virtualization/cluster-types/" \
        "$(jq -n \
            --arg name "$name" \
            --arg slug "$slug" \
            '{name:$name,slug:$slug}')")

    id=$(echo "$response" | jq -r '.id // empty')

    echo "$id"
}

# ============================================================
# GET OR CREATE CLUSTER GROUP
# ============================================================

get_or_create_cluster_group() {

    local name="$1"
    local slug

    slug=$(slugify "$name")

    local response
    local id

    response=$(api_get \
        "virtualization/cluster-groups/?name=$(urlencode "$name")")

    id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$id" ]; then
        echo "$id"
        return
    fi

    response=$(api_post \
        "virtualization/cluster-groups/" \
        "$(jq -n \
            --arg name "$name" \
            --arg slug "$slug" \
            '{name:$name,slug:$slug}')")

    id=$(echo "$response" | jq -r '.id // empty')

    echo "$id"
}

# ============================================================
# GET OR CREATE CLUSTER
# ============================================================

get_or_create_cluster() {

    local type_name="$1"
    local group_name="$2"
    local cluster_name="$3"

    local type_id
    local group_id
    local response
    local cluster_id

    type_id=$(get_or_create_cluster_type "$type_name")

    if [ -z "$type_id" ]; then
        error "Unable to create/find Cluster Type: $type_name"
        return 1
    fi

    group_id=$(get_or_create_cluster_group "$group_name")

    if [ -z "$group_id" ]; then
        error "Unable to create/find Cluster Group: $group_name"
        return 1
    fi

    response=$(api_get \
        "virtualization/clusters/?name=$(urlencode "$cluster_name")")

    cluster_id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$cluster_id" ]; then
        echo "Cluster already exists: $cluster_name" >&2
        echo "$cluster_id"
        return
    fi

    echo "Creating cluster: $cluster_name" >&2

    response=$(api_post \
        "virtualization/clusters/" \
        "$(jq -n \
            --arg name "$cluster_name" \
            --argjson type "$type_id" \
            --argjson group "$group_id" \
            --argjson site "$SITE_ID" \
            '{
                name:$name,
                type:$type,
                group:$group,
                site:$site
            }')")

    cluster_id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$cluster_id" ]; then
        echo "$response" >&2
        return 1
    fi

    echo "$cluster_id"
}

# ============================================================
# GET DEVICE
# ============================================================

get_device_id() {

    local hostname="$1"
    local response

    response=$(api_get \
        "dcim/devices/?name=$(urlencode "$hostname")")

    echo "$response" | jq -r '.results[0].id // empty'
}

# ============================================================
# CREATE OR UPDATE DEVICE
# ============================================================

create_or_update_device() {

    local hostname="$1"
    local cluster_id="$2"
    local status="$3"

    local device_id
    local response

    device_id=$(get_device_id "$hostname")

    if [ -n "$device_id" ]; then

        echo "Device already exists. Updating..." >&2

        response=$(api_patch \
            "dcim/devices/$device_id/" \
            "$(jq -n \
                --argjson cluster "$cluster_id" \
                --arg status "$status" \
                '{
                    cluster:$cluster,
                    status:$status
                }')")

        if ! echo "$response" | jq -e '.id' >/dev/null 2>&1; then
            echo "$response" >&2
            return 1
        fi

        echo "$device_id"
        return
    fi

    echo "Creating device..." >&2

    response=$(api_post \
        "dcim/devices/" \
        "$(jq -n \
            --arg name "$hostname" \
            --argjson device_type "$DEVICETYPE_ID" \
            --argjson role "$DEVICEROLE_ID" \
            --argjson site "$SITE_ID" \
            --argjson cluster "$cluster_id" \
            --arg status "$status" \
            '{
                name:$name,
                device_type:$device_type,
                role:$role,
                site:$site,
                cluster:$cluster,
                status:$status
            }')")

    device_id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$device_id" ]; then
        echo "$response" >&2
        return 1
    fi

    echo "$device_id"
}

# ============================================================
# GET INTERFACE
# ============================================================

get_interface_id() {

    local device_id="$1"
    local interface_name="$2"

    local response

    response=$(api_get \
        "dcim/interfaces/?device_id=$device_id&name=$(urlencode "$interface_name")")

    echo "$response" | jq -r '.results[0].id // empty'
}

# ============================================================
# CREATE OR UPDATE INTERFACE
# ============================================================

create_or_update_interface() {

    local device_id="$1"
    local interface_name="$2"

    local interface_id
    local response

    interface_id=$(get_interface_id "$device_id" "$interface_name")

    if [ -n "$interface_id" ]; then
        echo "$interface_id"
        return
    fi

    echo "Creating interface: $interface_name" >&2

    response=$(api_post \
        "dcim/interfaces/" \
        "$(jq -n \
            --argjson device "$device_id" \
            --arg name "$interface_name" \
            '{
                device:$device,
                name:$name,
                type:"1000base-t"
            }')")

    interface_id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$interface_id" ]; then
        echo "$response" >&2
        return 1
    fi

    echo "$interface_id"
}

# ============================================================
# GET IP
# ============================================================

get_ip_id() {

    local ipaddr="$1"
    local response

    response=$(api_get \
        "ipam/ip-addresses/?address=$(urlencode "$ipaddr")")

    echo "$response" | jq -r '.results[0].id // empty'
}

# ============================================================
# CREATE OR ASSIGN IP
# ============================================================

create_or_assign_ip() {

    local ipaddr="$1"
    local interface_id="$2"

    local ip_id
    local response

    ip_id=$(get_ip_id "$ipaddr")

    if [ -n "$ip_id" ]; then

        echo "IP already exists. Assigning to interface..." >&2

        response=$(api_patch \
            "ipam/ip-addresses/$ip_id/" \
            "$(jq -n \
                --argjson interface_id "$interface_id" \
                '{
                    assigned_object_type:"dcim.interface",
                    assigned_object_id:$interface_id
                }')")

        if ! echo "$response" | jq -e '.id' >/dev/null 2>&1; then
            echo "$response" >&2
            return 1
        fi

        echo "$ip_id"
        return
    fi

    echo "Creating IP: $ipaddr" >&2

    response=$(api_post \
        "ipam/ip-addresses/" \
        "$(jq -n \
            --arg address "$ipaddr" \
            --argjson interface_id "$interface_id" \
            '{
                address:$address,
                status:"active",
                assigned_object_type:"dcim.interface",
                assigned_object_id:$interface_id
            }')")

    ip_id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$ip_id" ]; then
        echo "$response" >&2
        return 1
    fi

    echo "$ip_id"
}

# ============================================================
# MAC ADDRESS
# ============================================================

create_or_assign_mac() {

    local mac="$1"
    local interface_id="$2"

    [ -z "$mac" ] && return 0

    local response
    local mac_id

    response=$(api_get \
        "dcim/mac-addresses/?mac_address=$(urlencode "$mac")")

    mac_id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$mac_id" ]; then

        response=$(api_patch \
            "dcim/mac-addresses/$mac_id/" \
            "$(jq -n \
                --argjson interface_id "$interface_id" \
                '{
                    assigned_object_type:"dcim.interface",
                    assigned_object_id:$interface_id
                }')")

    else

        response=$(api_post \
            "dcim/mac-addresses/" \
            "$(jq -n \
                --arg mac "$mac" \
                --argjson interface_id "$interface_id" \
                '{
                    mac_address:$mac,
                    assigned_object_type:"dcim.interface",
                    assigned_object_id:$interface_id
                }')")

        mac_id=$(echo "$response" | jq -r '.id // empty')
    fi

    if [ -z "$mac_id" ]; then
        echo "Warning: Failed creating MAC object" >&2
        echo "$response" >&2
        return 0
    fi

    response=$(api_patch \
        "dcim/interfaces/$interface_id/" \
        "$(jq -n \
            --argjson mac_id "$mac_id" \
            '{
                primary_mac_address:$mac_id
            }')")

    return 0
}

# ============================================================
# ASSIGN PRIMARY IP
# ============================================================

assign_primary_ip() {

    local device_id="$1"
    local ip_id="$2"

    local response

    response=$(api_patch \
        "dcim/devices/$device_id/" \
        "$(jq -n \
            --argjson ip_id "$ip_id" \
            '{
                primary_ip4:$ip_id
            }')")

    if ! echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo "$response"
        return 1
    fi

    return 0
}

# ============================================================
# GET TAG ID
# ============================================================

get_tag_id() {

    local tag_name="$1"
    local response

    response=$(api_get \
        "extras/tags/?name=$(urlencode "$tag_name")")

    echo "$response" | jq -r '.results[0].id // empty'
}

# ============================================================
# ASSIGN TAGS
# ============================================================

assign_tags() {

    local device_id="$1"
    local cluster_name="$2"

    local tags=()

    case "$cluster_name" in

        centos-07-servers)

            tags=(
                "centostorocky-context"
                "patch-context"
                "pxe-centos-context"
                "repo-config-context"
                "vmware-awx-context"
                "centos-patch-context"
            )
            ;;

        rocky-8-servers)

            tags=(
                "patch-el8-context"
                "pxe-rockyos-context"
                "repo-config-context"
                "vmware-awx-context"
                "rocky-patch-context"
            )
            ;;

        rocky-9-servers)

            tags=(
                "patch-el9-context"
                "pxe-rocky9-context"
                "repo-config-context"
                "vmware-awx-context"
                "rocky9-patch-context"
            )
            ;;

        *)

            warn "No predefined tags for cluster: $cluster_name"
            return 0
            ;;
    esac

    local tag_ids=()
    local tag
    local id

    echo "Assigning tags..."

    for tag in "${tags[@]}"
    do
        id=$(get_tag_id "$tag")

        if [ -n "$id" ]; then
            echo "  Adding tag: $tag"
            tag_ids+=("$id")
        else
            warn "  Tag not found: $tag"
        fi
    done

    [ "${#tag_ids[@]}" -eq 0 ] && return 0

    local tags_json
    local response

    tags_json=$(printf '%s\n' "${tag_ids[@]}" | jq -R 'tonumber' | jq -s '.')

    response=$(api_patch \
        "dcim/devices/$device_id/" \
        "$(jq -n \
            --argjson tags "$tags_json" \
            '{tags:$tags}')")

    if ! echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo "$response"
        return 1
    fi

    success "Tags assigned successfully"
}

# ============================================================
# CUSTOM FIELDS
# ============================================================

update_custom_fields() {

    local device_id="$1"
    local cpu="$2"
    local ram="$3"
    local disk="$4"
    local vmtype="$5"
    local kernel="$6"

    # Skip custom fields for manual devices
    if [ "$cpu" = "null" ]; then
        return 0
    fi

    local response

    response=$(api_patch \
        "dcim/devices/$device_id/" \
        "$(jq -n \
            --argjson cpu "$cpu" \
            --argjson ram "$ram" \
            --arg disk "$disk" \
            --arg vmtype "$vmtype" \
            --arg kernel "$kernel" \
            '{
                custom_fields:{
                    cpu_count:$cpu,
                    ram_gb:$ram,
                    disk_gb:$disk,
                    vm_type:$vmtype,
                    kernel:$kernel
                }
            }')")

    if ! echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        warn "Failed updating custom fields"
        echo "$response"
    fi
}

# ============================================================
# SSH COMMAND
# ============================================================

ssh_run() {

    local host="$1"
    local command="$2"

    sshpass -p "$SSH_PASS" \
        ssh \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$SSH_USER@$host" \
        "$command"
}

# ============================================================
# PROCESS DEVICE
# ============================================================

process_device() {

    local hostname="$1"
    local ipaddr="$2"
    local mode="$3"
    local cluster_id="$4"
    local cluster_name="$5"

    echo
    echo "------------------------------------------------------------"
    echo "Processing: $hostname"
    echo "------------------------------------------------------------"

    local iface=""
    local mac=""
    local cpu="null"
    local ram="null"
    local disk=""
    local vmtype=""
    local kernel=""
    local uptime=""

    if [ "$mode" = "manual" ]; then

        iface="eth0"

        echo "IP       : $ipaddr"
        echo "Mode     : Manual"
        echo "Rest data: Not required"

    else

        echo "Checking connectivity..."

        if ! ping -c1 -W2 "$hostname" >/dev/null 2>&1; then
            error "Host unreachable: $hostname"
            FAILED_LIST+="$hostname"$'\n'
            return
        fi

        success "Host reachable"

        echo "Discovering system information..."

        local iface_data

        iface_data=$(ssh_run "$hostname" \
            "ip -o -4 addr show scope global | head -1")

        iface=$(echo "$iface_data" | awk '{print $2}')

        if [ -z "$iface" ]; then
            error "Unable to detect interface"
            FAILED_LIST+="$hostname"$'\n'
            return
        fi

        ipaddr=$(echo "$iface_data" | awk '{print $4}')

        mac=$(ssh_run "$hostname" \
            "cat /sys/class/net/$iface/address" |
            tr '[:lower:]' '[:upper:]')

        cpu=$(ssh_run "$hostname" "nproc")

        ram=$(ssh_run "$hostname" \
            "awk '/MemTotal/ {printf \"%d\", (\$2/1024/1024)+0.5}' /proc/meminfo")

        disk=$(ssh_run "$hostname" \
            "lsblk -bdno SIZE | awk '{s+=\$1} END {printf \"%.0f GB\",s/1024/1024/1024}'")

        vmtype=$(ssh_run "$hostname" \
            "systemd-detect-virt 2>/dev/null || true")

        [ -z "$vmtype" ] && vmtype="Physical"

        kernel=$(ssh_run "$hostname" "uname -r")

        uptime=$(ssh_run "$hostname" "uptime -p")

        echo "Hostname : $hostname"
        echo "IP       : $ipaddr"
        echo "Interface: $iface"
        echo "MAC      : $mac"
        echo "CPU      : $cpu"
        echo "RAM      : $ram GB"
        echo "Disk     : $disk"
        echo "Type     : $vmtype"
        echo "Kernel   : $kernel"
        echo "Uptime   : $uptime"
    fi

    # --------------------------------------------------------
    # DEVICE
    # --------------------------------------------------------

    local device_id

    if ! device_id=$(create_or_update_device \
        "$hostname" \
        "$cluster_id" \
        "active"); then

        error "Failed creating/updating device: $hostname"
        FAILED_LIST+="$hostname"$'\n'
        return
    fi

    echo "Device ID: $device_id"

    # --------------------------------------------------------
    # INTERFACE
    # --------------------------------------------------------

    local interface_id

    if ! interface_id=$(create_or_update_interface \
        "$device_id" \
        "$iface"); then

        error "Failed creating interface: $iface"
        FAILED_LIST+="$hostname"$'\n'
        return
    fi

    echo "Interface ID: $interface_id"

    # --------------------------------------------------------
    # MAC
    # --------------------------------------------------------

    if [ -n "$mac" ]; then

        if ! create_or_assign_mac \
            "$mac" \
            "$interface_id"; then

            warn "MAC processing failed"
        fi
    fi

    # --------------------------------------------------------
    # IP
    # --------------------------------------------------------

    local ip_id

    if ! ip_id=$(create_or_assign_ip \
        "$ipaddr" \
        "$interface_id"); then

        error "Failed creating/assigning IP: $ipaddr"
        FAILED_LIST+="$hostname"$'\n'
        return
    fi

    echo "IP ID: $ip_id"

    # --------------------------------------------------------
    # PRIMARY IP
    # --------------------------------------------------------

    echo "Assigning Primary IP..."

    if ! assign_primary_ip \
        "$device_id" \
        "$ip_id"; then

        error "Failed assigning Primary IP"
        FAILED_LIST+="$hostname"$'\n'
        return
    fi

    success "Primary IP assigned successfully"

    # --------------------------------------------------------
    # CUSTOM FIELDS
    # --------------------------------------------------------

    update_custom_fields \
        "$device_id" \
        "$cpu" \
        "$ram" \
        "$disk" \
        "$vmtype" \
        "$kernel"

    # --------------------------------------------------------
    # TAGS
    # --------------------------------------------------------

    if ! assign_tags \
        "$device_id" \
        "$cluster_name"; then

        error "Failed assigning tags"
        FAILED_LIST+="$hostname"$'\n'
        return
    fi

    echo
    success "✓ Finished: $hostname"

    SUCCESS_LIST+="$hostname"$'\n'
}

# ============================================================
# MAIN
# ============================================================

banner

check_dependencies
check_netbox

# ============================================================
# STEP 1 - CENTOS 7
# ============================================================

header "STEP 1 - CENTOS 7 DEVICES"

TYPE_NAME="Physical"
GROUP_NAME="centos-07-servers"
CLUSTER_NAME="centos-07-servers"

echo "Cluster Type : $TYPE_NAME"
echo "Cluster Group: $GROUP_NAME"
echo "Cluster Name : $CLUSTER_NAME"

CLUSTER_ID=$(get_or_create_cluster \
    "$TYPE_NAME" \
    "$GROUP_NAME" \
    "$CLUSTER_NAME")

echo "Cluster ID: $CLUSTER_ID"

process_device \
    "cent-07-01.vgs.com" \
    "192.168.253.131/24" \
    "manual" \
    "$CLUSTER_ID" \
    "$CLUSTER_NAME"

process_device \
    "cent-07-02.vgs.com" \
    "192.168.253.132/24" \
    "manual" \
    "$CLUSTER_ID" \
    "$CLUSTER_NAME"

# ============================================================
# STEP 2 - ROCKY 8
# ============================================================

header "STEP 2 - ROCKY 8 DEVICES - AUTOMATIC DISCOVERY"

TYPE_NAME="Physical"
GROUP_NAME="rocky-8-servers"
CLUSTER_NAME="rocky-8-servers"

echo "Cluster Type : $TYPE_NAME"
echo "Cluster Group: $GROUP_NAME"
echo "Cluster Name : $CLUSTER_NAME"

CLUSTER_ID=$(get_or_create_cluster \
    "$TYPE_NAME" \
    "$GROUP_NAME" \
    "$CLUSTER_NAME")

echo "Cluster ID: $CLUSTER_ID"

process_device \
    "netbox.vgs.com" \
    "192.168.253.143/24" \
    "auto" \
    "$CLUSTER_ID" \
    "$CLUSTER_NAME"

process_device \
    "ansible-server-01.vgs.com" \
    "192.168.253.145/24" \
    "auto" \
    "$CLUSTER_ID" \
    "$CLUSTER_NAME"

# ============================================================
# STEP 3 - ROCKY 9
# ============================================================

header "STEP 3 - ROCKY 9 DEVICE"

TYPE_NAME="Physical"
GROUP_NAME="rocky-9-servers"
CLUSTER_NAME="rocky-9-servers"

echo "Cluster Type : $TYPE_NAME"
echo "Cluster Group: $GROUP_NAME"
echo "Cluster Name : $CLUSTER_NAME"

CLUSTER_ID=$(get_or_create_cluster \
    "$TYPE_NAME" \
    "$GROUP_NAME" \
    "$CLUSTER_NAME")

echo "Cluster ID: $CLUSTER_ID"

process_device \
    "rocky-09-01.vgs.com" \
    "192.168.253.151/24" \
    "manual" \
    "$CLUSTER_ID" \
    "$CLUSTER_NAME"

# ============================================================
# SUMMARY
# ============================================================

echo
echo "============================================================"
echo "                    FINAL SUMMARY"
echo "============================================================"
echo

echo -e "${GREEN}SUCCESSFUL HOSTS${NC}"

if [ -z "$SUCCESS_LIST" ]; then
    echo "0"
else
    echo "$SUCCESS_LIST"
fi

echo
echo -e "${RED}FAILED HOSTS${NC}"

if [ -z "$FAILED_LIST" ]; then
    echo "0"
else
    echo "$FAILED_LIST"
fi

SUCCESS_COUNT=$(echo "$SUCCESS_LIST" | sed '/^$/d' | wc -l)
FAILED_COUNT=$(echo "$FAILED_LIST" | sed '/^$/d' | wc -l)

echo
echo "Success Count: $SUCCESS_COUNT"
echo "Failed Count : $FAILED_COUNT"

echo
echo "============================================================"

if [ "$FAILED_COUNT" -eq 0 ]; then
    success "NETBOX SPECIFIC DEVICE CREATION COMPLETED"
else
    error "NETBOX SPECIFIC DEVICE CREATION COMPLETED WITH FAILURES"
fi

echo "============================================================"
