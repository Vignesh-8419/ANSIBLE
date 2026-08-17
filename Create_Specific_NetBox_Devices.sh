#!/bin/bash

set -u
set -o pipefail

# ============================================================
# NETBOX SPECIFIC DEVICE CREATION TOOL
#
# Features:
# - Create or update clusters
# - Create or update devices
# - Supports short hostname -> FQDN migration
# - Safe existing IP handling
# - Prevents accidental IP reassignment
# - Reuses existing interfaces
# - Syncs MAC addresses
# - Updates custom fields for auto-discovered hosts
# - Assigns primary IPs
# - Assigns tags
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="REPLACE_WITH_NETBOX_TOKEN"
HDR="Content-Type: application/json"

SSH_USER="admin"
SSH_PASS="REPLACE_WITH_SSH_PASSWORD"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1


# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'


# ============================================================
# RESULTS
# ============================================================

SUCCESS_LIST=""
FAILED_LIST=""


# ============================================================
# DISPLAY FUNCTIONS
# ============================================================

header() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

info() {
    echo -e "${BLUE}$1${NC}"
}

success() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

error() {
    echo -e "${RED}$1${NC}"
}


# ============================================================
# DEPENDENCY CHECK
# ============================================================

check_dependencies() {

    info "Checking dependencies..."

    for cmd in curl jq ping ssh sshpass
    do
        if ! command -v "$cmd" >/dev/null 2>&1; then

            error "Missing dependency: $cmd"

            case "$cmd" in
                sshpass)
                    echo "Install with: yum install -y sshpass"
                    ;;
                jq)
                    echo "Install with: yum install -y jq"
                    ;;
                *)
                    echo "Install the package providing: $cmd"
                    ;;
            esac

            exit 1
        fi
    done

    success "Dependencies OK"
}


# ============================================================
# NETBOX API CHECK
# ============================================================

check_netbox() {

    echo
    info "Checking NetBox API..."

    local http_code

    http_code=$(curl -sk \
        -o /dev/null \
        -w "%{http_code}" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/status/")

    if [ "$http_code" != "200" ]; then

        error "NetBox API check failed"
        error "HTTP Code: $http_code"

        exit 1
    fi

    success "NetBox API reachable"
}


# ============================================================
# HELPERS
# ============================================================

urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

slugify() {
    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr ' ' '-' |
        sed 's/[^a-z0-9-]//g'
}


# ============================================================
# GET DEVICE BY EXACT NAME
# ============================================================

get_device_id_by_name() {

    local hostname="$1"
    local encoded_name

    encoded_name=$(urlencode "$hostname")

    curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/dcim/devices/?name=$encoded_name" |
        jq -r '.results[0].id // empty'
}


# ============================================================
# GET OR CREATE CLUSTER TYPE
# ============================================================

get_or_create_cluster_type() {

    local name="$1"
    local encoded_name
    local id
    local slug
    local response

    encoded_name=$(urlencode "$name")

    id=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/virtualization/cluster-types/?name=$encoded_name" |
        jq -r '.results[0].id // empty')

    if [ -n "$id" ]; then
        echo "$id"
        return 0
    fi

    slug=$(slugify "$name")

    response=$(curl -sk -X POST \
        "$NETBOX_URL/virtualization/cluster-types/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --arg name "$name" \
            --arg slug "$slug" \
            '{
                name: $name,
                slug: $slug
            }')")

    id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$id" ]; then

        error "Failed creating Cluster Type: $name" >&2
        echo "$response" | jq . >&2

        return 1
    fi

    echo "$id"
}


# ============================================================
# GET OR CREATE CLUSTER GROUP
# ============================================================

get_or_create_cluster_group() {

    local name="$1"
    local encoded_name
    local id
    local slug
    local response

    encoded_name=$(urlencode "$name")

    id=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/virtualization/cluster-groups/?name=$encoded_name" |
        jq -r '.results[0].id // empty')

    if [ -n "$id" ]; then
        echo "$id"
        return 0
    fi

    slug=$(slugify "$name")

    response=$(curl -sk -X POST \
        "$NETBOX_URL/virtualization/cluster-groups/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --arg name "$name" \
            --arg slug "$slug" \
            '{
                name: $name,
                slug: $slug
            }')")

    id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$id" ]; then

        error "Failed creating Cluster Group: $name" >&2
        echo "$response" | jq . >&2

        return 1
    fi

    echo "$id"
}


# ============================================================
# GET OR CREATE CLUSTER
# ============================================================

get_or_create_cluster() {

    local cluster_name="$1"
    local type_id="$2"
    local group_id="$3"

    local encoded_name
    local id
    local response

    encoded_name=$(urlencode "$cluster_name")

    id=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/virtualization/clusters/?name=$encoded_name" |
        jq -r '.results[0].id // empty')

    if [ -n "$id" ]; then

        echo "Cluster already exists: $cluster_name" >&2
        echo "$id"

        return 0
    fi

    echo "Creating cluster: $cluster_name" >&2

    response=$(curl -sk -X POST \
        "$NETBOX_URL/virtualization/clusters/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --arg name "$cluster_name" \
            --argjson type "$type_id" \
            --argjson group "$group_id" \
            --argjson site "$SITE_ID" \
            '{
                name: $name,
                type: $type,
                group: $group,
                scope_type: "dcim.site",
                scope_id: $site
            }')")

    id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$id" ]; then

        error "Failed creating cluster: $cluster_name" >&2
        echo "$response" | jq . >&2

        return 1
    fi

    echo "$id"
}


# ============================================================
# CREATE OR UPDATE DEVICE
#
# Supports:
#
# Existing:
#   cent-07-02
#
# Requested:
#   cent-07-02.vgs.com
#
# Result:
#   Existing device is renamed instead of creating a duplicate.
# ============================================================

create_or_update_device() {

    local hostname="$1"
    local cluster_id="$2"
    local device_status="$3"

    local short_hostname
    local device_id
    local response

    # --------------------------------------------------------
    # FIRST: Search exact hostname
    # --------------------------------------------------------

    device_id=$(get_device_id_by_name "$hostname")

    # --------------------------------------------------------
    # SECOND: If FQDN does not exist, search short hostname
    # --------------------------------------------------------

    if [ -z "$device_id" ] && [[ "$hostname" == *.* ]]; then

        short_hostname="${hostname%%.*}"

        device_id=$(get_device_id_by_name "$short_hostname")

        if [ -n "$device_id" ]; then

            warn "Existing device found with short hostname: $short_hostname"
            info "Migrating hostname: $short_hostname -> $hostname"
        fi
    fi

    # --------------------------------------------------------
    # UPDATE EXISTING DEVICE
    # --------------------------------------------------------

    if [ -n "$device_id" ]; then

        echo "Device already exists. Updating..." >&2

        response=$(curl -sk -X PATCH \
            "$NETBOX_URL/dcim/devices/$device_id/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "$(jq -n \
                --arg name "$hostname" \
                --argjson cluster "$cluster_id" \
                --arg status "$device_status" \
                '{
                    name: $name,
                    cluster: $cluster,
                    status: $status
                }')")

        if [ "$(echo "$response" | jq -r '.id // empty')" != "$device_id" ]; then

            error "Failed updating device: $hostname" >&2
            echo "$response" | jq . >&2

            return 1
        fi

        echo "$device_id"

        return 0
    fi

    # --------------------------------------------------------
    # CREATE NEW DEVICE
    # --------------------------------------------------------

    echo "Creating device..." >&2

    response=$(curl -sk -X POST \
        "$NETBOX_URL/dcim/devices/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --arg name "$hostname" \
            --argjson device_type "$DEVICETYPE_ID" \
            --argjson role "$DEVICEROLE_ID" \
            --argjson site "$SITE_ID" \
            --argjson cluster "$cluster_id" \
            --arg status "$device_status" \
            '{
                name: $name,
                device_type: $device_type,
                role: $role,
                site: $site,
                cluster: $cluster,
                status: $status
            }')")

    device_id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$device_id" ]; then

        error "Failed creating device: $hostname" >&2
        echo "$response" | jq . >&2

        return 1
    fi

    echo "$device_id"
}


# ============================================================
# GET OR CREATE INTERFACE
# ============================================================

get_or_create_interface() {

    local device_id="$1"
    local interface_name="$2"

    local interface_id
    local response

    interface_id=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/dcim/interfaces/?device_id=$device_id" |
        jq -r --arg name "$interface_name" \
        '.results[] | select(.name == $name) | .id' |
        head -1)

    if [ -n "$interface_id" ]; then

        echo "Interface already exists: $interface_name" >&2
        echo "$interface_id"

        return 0
    fi

    echo "Creating interface: $interface_name" >&2

    response=$(curl -sk -X POST \
        "$NETBOX_URL/dcim/interfaces/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --argjson device "$device_id" \
            --arg name "$interface_name" \
            '{
                device: $device,
                name: $name,
                type: "1000base-t"
            }')")

    interface_id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$interface_id" ]; then

        error "Failed creating interface" >&2
        echo "$response" | jq . >&2

        return 1
    fi

    echo "$interface_id"
}


# ============================================================
# GET OR CREATE MAC
# ============================================================

sync_mac_address() {

    local mac="$1"
    local interface_id="$2"

    [ -z "$mac" ] && return 0

    local encoded_mac
    local mac_id
    local response

    encoded_mac=$(urlencode "$mac")

    mac_id=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/dcim/mac-addresses/?mac_address=$encoded_mac" |
        jq -r '.results[0].id // empty')

    # --------------------------------------------------------
    # CREATE MAC
    # --------------------------------------------------------

    if [ -z "$mac_id" ]; then

        response=$(curl -sk -X POST \
            "$NETBOX_URL/dcim/mac-addresses/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "$(jq -n \
                --arg mac "$mac" \
                --argjson interface "$interface_id" \
                '{
                    mac_address: $mac,
                    assigned_object_type: "dcim.interface",
                    assigned_object_id: $interface
                }')")

        mac_id=$(echo "$response" | jq -r '.id // empty')

        if [ -z "$mac_id" ]; then

            warn "Warning: Failed creating MAC object"
            echo "$response" | jq .

            return 0
        fi

    # --------------------------------------------------------
    # UPDATE MAC
    # --------------------------------------------------------

    else

        response=$(curl -sk -X PATCH \
            "$NETBOX_URL/dcim/mac-addresses/$mac_id/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "$(jq -n \
                --argjson interface "$interface_id" \
                '{
                    assigned_object_type: "dcim.interface",
                    assigned_object_id: $interface
                }')")

        if [ -z "$(echo "$response" | jq -r '.id // empty')" ]; then

            warn "Warning: Failed updating MAC object"
            echo "$response" | jq .

            return 0
        fi
    fi

    # --------------------------------------------------------
    # SET PRIMARY MAC
    # --------------------------------------------------------

    response=$(curl -sk -X PATCH \
        "$NETBOX_URL/dcim/interfaces/$interface_id/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --argjson mac_id "$mac_id" \
            '{
                primary_mac_address: $mac_id
            }')")

    if [ -z "$(echo "$response" | jq -r '.id // empty')" ]; then
        warn "Warning: Failed assigning primary MAC"
    fi
}


# ============================================================
# GET OR CREATE / ASSIGN IP
#
# SAFE VERSION:
#
# Existing IP + same interface:
#   Do nothing
#
# Existing IP + unassigned:
#   Assign safely
#
# Existing IP + different interface:
#   STOP - do not steal the IP
# ============================================================

sync_ip_address() {

    local ip_address="$1"
    local interface_id="$2"

    local encoded_ip
    local response
    local ip_id
    local assigned_object_type
    local assigned_object_id

    encoded_ip=$(urlencode "$ip_address")

    response=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/ipam/ip-addresses/?address=$encoded_ip")

    ip_id=$(echo "$response" |
        jq -r '.results[0].id // empty')

    # --------------------------------------------------------
    # IP ALREADY EXISTS
    # --------------------------------------------------------

    if [ -n "$ip_id" ]; then

        assigned_object_type=$(echo "$response" |
            jq -r '.results[0].assigned_object_type // empty')

        assigned_object_id=$(echo "$response" |
            jq -r '.results[0].assigned_object_id // empty')

        echo "IP already exists." >&2
        echo "IP ID: $ip_id" >&2

        # ----------------------------------------------------
        # IP ALREADY BELONGS TO THIS INTERFACE
        # ----------------------------------------------------

        if [ "$assigned_object_type" = "dcim.interface" ] &&
           [ "$assigned_object_id" = "$interface_id" ]; then

            echo "IP is already assigned to this interface." >&2

            echo "$ip_id"
            return 0
        fi

        # ----------------------------------------------------
        # IP EXISTS BUT IS UNASSIGNED
        # ----------------------------------------------------

        if [ -z "$assigned_object_id" ] ||
           [ "$assigned_object_id" = "null" ]; then

            echo "IP is unassigned. Assigning to interface..." >&2

            response=$(curl -sk -X PATCH \
                "$NETBOX_URL/ipam/ip-addresses/$ip_id/" \
                -H "$HDR" \
                -H "Authorization: Token $NETBOX_TOKEN" \
                -d "$(jq -n \
                    --argjson interface "$interface_id" \
                    '{
                        assigned_object_type: "dcim.interface",
                        assigned_object_id: $interface
                    }')")

            if [ -z "$(echo "$response" | jq -r '.id // empty')" ]; then

                error "Failed assigning existing IP" >&2
                echo "$response" | jq . >&2

                return 1
            fi

            echo "$ip_id"
            return 0
        fi

        # ----------------------------------------------------
        # IP BELONGS TO ANOTHER INTERFACE
        # ----------------------------------------------------

        error "IP $ip_address is already assigned to another interface." >&2
        error "Current Interface ID : $assigned_object_id" >&2
        error "Requested Interface ID: $interface_id" >&2
        error "Automatic reassignment blocked." >&2

        return 1
    fi

    # --------------------------------------------------------
    # CREATE NEW IP
    # --------------------------------------------------------

    echo "Creating IP: $ip_address" >&2

    response=$(curl -sk -X POST \
        "$NETBOX_URL/ipam/ip-addresses/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --arg address "$ip_address" \
            --argjson interface "$interface_id" \
            '{
                address: $address,
                assigned_object_type: "dcim.interface",
                assigned_object_id: $interface,
                status: "active"
            }')")

    ip_id=$(echo "$response" | jq -r '.id // empty')

    if [ -z "$ip_id" ]; then

        error "Failed creating IP" >&2
        echo "$response" | jq . >&2

        return 1
    fi

    echo "$ip_id"
}


# ============================================================
# ASSIGN PRIMARY IP
# ============================================================

assign_primary_ip() {

    local device_id="$1"
    local ip_id="$2"

    local response

    echo "Assigning Primary IP..."

    response=$(curl -sk -X PATCH \
        "$NETBOX_URL/dcim/devices/$device_id/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --argjson ip_id "$ip_id" \
            '{
                primary_ip4: $ip_id
            }')")

    if [ -z "$(echo "$response" | jq -r '.id // empty')" ]; then

        error "Failed assigning Primary IP"
        echo "$response" | jq .

        return 1
    fi

    success "Primary IP assigned successfully"
}


# ============================================================
# GET TAG ID
# ============================================================

get_tag_id() {

    local tag_name="$1"
    local encoded_name

    encoded_name=$(urlencode "$tag_name")

    curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/extras/tags/?name=$encoded_name" |
        jq -r '.results[0].id // empty'
}


# ============================================================
# ASSIGN TAGS
# ============================================================

assign_tags() {

    local device_id="$1"
    local cluster_name="$2"

    local -a tags
    local -a tag_ids

    tag_ids=()

    case "$cluster_name" in

        "centos-07-servers")
            tags=(
                "centostorocky-context"
                "patch-context"
                "pxe-centos-context"
                "repo-config-context"
                "vmware-awx-context"
                "centos-patch-context"
            )
            ;;

        "rocky-8-servers")
            tags=(
                "patch-el8-context"
                "pxe-rockyos-context"
                "repo-config-context"
                "vmware-awx-context"
                "rocky-patch-context"
            )
            ;;

        "rocky-9-servers")
            tags=(
                "patch-el9-context"
                "pxe-rocky9-context"
                "repo-config-context"
                "vmware-awx-context"
                "rocky9-patch-context"
            )
            ;;

        *)
            tags=()
            ;;
    esac

    if [ "${#tags[@]}" -eq 0 ]; then

        warn "No predefined tags for cluster: $cluster_name"

        return 0
    fi

    echo "Assigning tags..."

    local tag
    local tag_id

    for tag in "${tags[@]}"
    do
        tag_id=$(get_tag_id "$tag")

        if [ -n "$tag_id" ]; then

            echo "  Adding tag: $tag"
            tag_ids+=("$tag_id")

        else

            warn "  Tag not found: $tag"
        fi
    done

    if [ "${#tag_ids[@]}" -eq 0 ]; then

        warn "No tags found to assign"

        return 0
    fi

    local json_tags
    local response

    json_tags=$(printf '%s\n' "${tag_ids[@]}" |
        jq -R 'tonumber' |
        jq -s '.')

    response=$(curl -sk -X PATCH \
        "$NETBOX_URL/dcim/devices/$device_id/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --argjson tags "$json_tags" \
            '{
                tags: $tags
            }')")

    if [ -z "$(echo "$response" | jq -r '.id // empty')" ]; then

        warn "Failed assigning tags"
        echo "$response" | jq .

        return 0
    fi

    success "Tags assigned successfully"
}


# ============================================================
# UPDATE CUSTOM FIELDS - AUTO ONLY
# ============================================================

update_custom_fields() {

    local device_id="$1"
    local cpu="$2"
    local ram="$3"
    local disk="$4"
    local vm_type="$5"
    local kernel="$6"

    local response

    response=$(curl -sk -X PATCH \
        "$NETBOX_URL/dcim/devices/$device_id/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$(jq -n \
            --argjson cpu "$cpu" \
            --argjson ram "$ram" \
            --argjson disk "$disk" \
            --arg vm_type "$vm_type" \
            --arg kernel "$kernel" \
            '{
                custom_fields: {
                    cpu_count: $cpu,
                    ram_gb: $ram,
                    disk_gb: $disk,
                    vm_type: $vm_type,
                    kernel: $kernel
                }
            }')")

    if [ -z "$(echo "$response" | jq -r '.id // empty')" ]; then

        warn "Failed updating custom fields"
        echo "$response" | jq .
    fi
}


# ============================================================
# SSH COMMAND
# ============================================================

remote_cmd() {

    local host="$1"
    local command="$2"

    sshpass -p "$SSH_PASS" \
        ssh \
        -o ConnectTimeout=8 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$host" \
        "$command"
}


# ============================================================
# AUTOMATIC DISCOVERY
# ============================================================

discover_host() {

    local host="$1"

    echo "Checking connectivity..."

    if ! ping -c1 -W2 "$host" >/dev/null 2>&1; then

        error "Host unreachable"

        return 1
    fi

    if ! remote_cmd "$host" "echo ok" >/dev/null 2>&1; then

        error "SSH connection failed"

        return 1
    fi

    success "Host reachable"
    echo "Discovering system information..."

    DISCOVER_HOSTNAME=$(remote_cmd "$host" \
        "hostname -f 2>/dev/null || hostname" |
        tr -d '\r' |
        xargs)

    local iface_data

    iface_data=$(remote_cmd "$host" \
        "ip -o -4 addr show scope global | head -1")

    DISCOVER_IFACE=$(echo "$iface_data" | awk '{print $2}')
    DISCOVER_IP=$(echo "$iface_data" | awk '{print $4}')

    if [ -z "$DISCOVER_IP" ]; then

        error "Unable to determine IP address"

        return 1
    fi

    DISCOVER_MAC=$(remote_cmd "$host" \
        "cat /sys/class/net/$DISCOVER_IFACE/address 2>/dev/null" |
        tr '[:lower:]' '[:upper:]' |
        tr -d '\r' |
        xargs)

    DISCOVER_CPU=$(remote_cmd "$host" \
        "nproc" |
        xargs)

    DISCOVER_RAM=$(remote_cmd "$host" \
        "awk '/MemTotal/ {printf \"%d\", (\$2/1024/1024)+0.5}' /proc/meminfo" |
        xargs)

    # Integer GB for NetBox custom field
    DISCOVER_DISK=$(remote_cmd "$host" \
        "lsblk -bdno SIZE | awk '{s+=\$1} END {printf \"%d\", s/1024/1024/1024}'" |
        xargs)

    DISCOVER_VMTYPE=$(remote_cmd "$host" \
        "systemd-detect-virt 2>/dev/null || true" |
        tr -d '\r' |
        xargs)

    [ -z "$DISCOVER_VMTYPE" ] && DISCOVER_VMTYPE="Physical"

    DISCOVER_KERNEL=$(remote_cmd "$host" \
        "uname -r" |
        xargs)

    DISCOVER_UPTIME=$(remote_cmd "$host" \
        "uptime -p" |
        xargs)

    return 0
}


# ============================================================
# PROCESS DEVICE
#
# mode=auto
#   - Discover information using SSH
#   - Status ACTIVE
#
# mode=manual
#   - Use supplied hostname/IP
#   - Status STAGED
# ============================================================

process_device() {

    local input_hostname="$1"
    local input_ip="$2"
    local mode="$3"
    local cluster_id="$4"
    local cluster_name="$5"

    local hostname
    local ip_address
    local interface
    local mac
    local cpu
    local ram
    local disk
    local vm_type
    local kernel
    local uptime
    local device_status

    echo
    echo "------------------------------------------------------------"
    echo "Processing: $input_hostname"
    echo "------------------------------------------------------------"

    # --------------------------------------------------------
    # AUTO MODE
    # --------------------------------------------------------

    if [ "$mode" = "auto" ]; then

        if ! discover_host "$input_hostname"; then

            FAILED_LIST+="$input_hostname"$'\n'

            return
        fi

        hostname="$DISCOVER_HOSTNAME"
        ip_address="$DISCOVER_IP"
        interface="$DISCOVER_IFACE"
        mac="$DISCOVER_MAC"
        cpu="$DISCOVER_CPU"
        ram="$DISCOVER_RAM"
        disk="$DISCOVER_DISK"
        vm_type="$DISCOVER_VMTYPE"
        kernel="$DISCOVER_KERNEL"
        uptime="$DISCOVER_UPTIME"

        device_status="active"

        echo "Hostname : $hostname"
        echo "IP       : $ip_address"
        echo "Interface: $interface"
        echo "MAC      : ${mac:-N/A}"
        echo "CPU      : $cpu"
        echo "RAM      : $ram GB"
        echo "Disk     : $disk GB"
        echo "Type     : $vm_type"
        echo "Kernel   : $kernel"
        echo "Uptime   : $uptime"
        echo "Status   : $device_status"

    # --------------------------------------------------------
    # MANUAL MODE
    # --------------------------------------------------------

    else

        hostname="$input_hostname"
        ip_address="$input_ip"

        device_status="staged"

        interface="eth0"
        mac=""
        cpu=""
        ram=""
        disk=""
        vm_type=""
        kernel=""
        uptime=""

        echo "IP       : $ip_address"
        echo "Mode     : Manual"
        echo "Rest data: Not required"
        echo "Status   : $device_status"
    fi


    # --------------------------------------------------------
    # CREATE / UPDATE DEVICE
    # --------------------------------------------------------

    local device_id

    if ! device_id=$(create_or_update_device \
        "$hostname" \
        "$cluster_id" \
        "$device_status"); then

        error "Failed to create/update device: $hostname"

        FAILED_LIST+="$hostname"$'\n'

        return
    fi

    echo "Device ID: $device_id"


    # --------------------------------------------------------
    # INTERFACE
    # --------------------------------------------------------

    local interface_id

    if ! interface_id=$(get_or_create_interface \
        "$device_id" \
        "$interface"); then

        error "Failed processing interface for: $hostname"

        FAILED_LIST+="$hostname"$'\n'

        return
    fi

    echo "Interface ID: $interface_id"


    # --------------------------------------------------------
    # MAC - AUTO ONLY
    # --------------------------------------------------------

    if [ "$mode" = "auto" ] && [ -n "$mac" ]; then

        sync_mac_address "$mac" "$interface_id"
    fi


    # --------------------------------------------------------
    # IP
    # --------------------------------------------------------

    local ip_id

    if ! ip_id=$(sync_ip_address \
        "$ip_address" \
        "$interface_id"); then

        error "Failed processing IP: $ip_address"

        FAILED_LIST+="$hostname"$'\n'

        return
    fi

    echo "IP ID: $ip_id"


    # --------------------------------------------------------
    # PRIMARY IP
    # --------------------------------------------------------

    if ! assign_primary_ip "$device_id" "$ip_id"; then

        FAILED_LIST+="$hostname"$'\n'

        return
    fi


    # --------------------------------------------------------
    # CUSTOM FIELDS - AUTO ONLY
    # --------------------------------------------------------

    if [ "$mode" = "auto" ]; then

        update_custom_fields \
            "$device_id" \
            "$cpu" \
            "$ram" \
            "$disk" \
            "$vm_type" \
            "$kernel"
    fi


    # --------------------------------------------------------
    # TAGS
    # --------------------------------------------------------

    assign_tags "$device_id" "$cluster_name"


    echo
    success "✓ Finished: $hostname"

    SUCCESS_LIST+="$hostname"$'\n'
}


# ============================================================
# MAIN
# ============================================================

clear

echo
echo "============================================================"
echo "        NETBOX SPECIFIC DEVICE CREATION TOOL"
echo "============================================================"

check_dependencies
check_netbox


# ============================================================
# STEP 1 - CENTOS 7 MANUAL DEVICES
# STATUS = STAGED
# ============================================================

header "STEP 1 - CENTOS 7 DEVICES"

CLUSTER_TYPE_NAME="Physical"
CLUSTER_GROUP_NAME="centos-07-servers"
CLUSTER_NAME="centos-07-servers"

echo "Cluster Type : $CLUSTER_TYPE_NAME"
echo "Cluster Group: $CLUSTER_GROUP_NAME"
echo "Cluster Name : $CLUSTER_NAME"

TYPE_ID=$(get_or_create_cluster_type "$CLUSTER_TYPE_NAME") || exit 1

GROUP_ID=$(get_or_create_cluster_group "$CLUSTER_GROUP_NAME") || exit 1

CLUSTER_ID=$(get_or_create_cluster \
    "$CLUSTER_NAME" \
    "$TYPE_ID" \
    "$GROUP_ID") || exit 1

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
# STEP 2 - ROCKY 8 AUTO DISCOVERY
# STATUS = ACTIVE
# ============================================================

header "STEP 2 - ROCKY 8 DEVICES - AUTOMATIC DISCOVERY"

CLUSTER_TYPE_NAME="Physical"
CLUSTER_GROUP_NAME="rocky-8-servers"
CLUSTER_NAME="rocky-8-servers"

echo "Cluster Type : $CLUSTER_TYPE_NAME"
echo "Cluster Group: $CLUSTER_GROUP_NAME"
echo "Cluster Name : $CLUSTER_NAME"

TYPE_ID=$(get_or_create_cluster_type "$CLUSTER_TYPE_NAME") || exit 1

GROUP_ID=$(get_or_create_cluster_group "$CLUSTER_GROUP_NAME") || exit 1

CLUSTER_ID=$(get_or_create_cluster \
    "$CLUSTER_NAME" \
    "$TYPE_ID" \
    "$GROUP_ID") || exit 1

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
# STEP 3 - ROCKY 9 MANUAL DEVICE
# STATUS = STAGED
# ============================================================

header "STEP 3 - ROCKY 9 DEVICE"

CLUSTER_TYPE_NAME="Physical"
CLUSTER_GROUP_NAME="rocky-9-servers"
CLUSTER_NAME="rocky-9-servers"

echo "Cluster Type : $CLUSTER_TYPE_NAME"
echo "Cluster Group: $CLUSTER_GROUP_NAME"
echo "Cluster Name : $CLUSTER_NAME"

TYPE_ID=$(get_or_create_cluster_type "$CLUSTER_TYPE_NAME") || exit 1

GROUP_ID=$(get_or_create_cluster_group "$CLUSTER_GROUP_NAME") || exit 1

CLUSTER_ID=$(get_or_create_cluster \
    "$CLUSTER_NAME" \
    "$TYPE_ID" \
    "$GROUP_ID") || exit 1

echo "Cluster ID: $CLUSTER_ID"


process_device \
    "rocky-09-01.vgs.com" \
    "192.168.253.151/24" \
    "manual" \
    "$CLUSTER_ID" \
    "$CLUSTER_NAME"


# ============================================================
# FINAL SUMMARY
# ============================================================

header "FINAL SUMMARY"

echo -e "${GREEN}SUCCESSFUL HOSTS${NC}"

SUCCESS_COUNT=$(echo "$SUCCESS_LIST" |
    sed '/^$/d' |
    wc -l)

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "0"
else
    echo "$SUCCESS_LIST"
fi

echo
echo -e "${RED}FAILED HOSTS${NC}"

FAILED_COUNT=$(echo "$FAILED_LIST" |
    sed '/^$/d' |
    wc -l)

if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "0"
else
    echo "$FAILED_LIST"
fi

echo
echo "Success Count: $SUCCESS_COUNT"
echo "Failed Count : $FAILED_COUNT"

echo
echo "============================================================"
echo "NETBOX SPECIFIC DEVICE CREATION COMPLETED"
echo "============================================================"
