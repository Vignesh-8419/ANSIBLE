#!/bin/bash

### =========================
### Detect primary interface first
### =========================
iface=$(ip -o -4 addr show up primary scope global | awk '{print $2}' | head -n1)

if [ -z "$iface" ]; then
    echo "ERROR: No active interface found. Exiting."
    exit 1
fi

echo "Detected interface: $iface"

### =========================
### Ensure default route via 192.168.253.2
### =========================
default_gw_required="192.168.253.2"
current_default=$(ip route | awk '/default/ {print $3}')

if [ "$current_default" != "$default_gw_required" ]; then
    echo "Default route via $default_gw_required not found → adding"
    ip route add default via $default_gw_required dev "$iface"
    echo "Default route added via $default_gw_required dev $iface"
else
    echo "Default route via $default_gw_required already exists"
fi

### =========================
### Detect ALTNAME (if present) for NetworkManager profile
### =========================
altname=$(ip -o link show "$iface" | grep -o 'altname [^ ]*' | awk '{print $2}')
if [ -n "$altname" ]; then
    profilename="$altname"
else
    profilename="$iface"
fi
echo "NetworkManager profile name will be: $profilename"

### =========================
### Detect IP, CIDR, Gateway
### =========================
ip_full=$(ip -4 addr show "$iface" | awk '/inet /{print $2}')
ip_addr=${ip_full%/*}
cidr=${ip_full#*/}

gateway=$default_gw_required

### =========================
### CIDR → Netmask conversion
### =========================
cidr2mask() {
    local i mask=""
    local full=$(($1/8))
    local remain=$(($1%8))

    for i in {0..3}; do
        if [ $i -lt $full ]; then
            mask+="255"
        elif [ $i -eq $full ]; then
            mask+="$((256 - 2**(8-remain)))"
        else
            mask+="0"
        fi
        [[ $i -lt 3 ]] && mask+="."
    done
    echo $mask
}

netmask=$(cidr2mask "$cidr")

### =========================
### Remove old ifcfg file to prevent conflicts
### =========================
cfg="/etc/sysconfig/network-scripts/ifcfg-${iface}"
if [ -f "$cfg" ]; then
    echo "Removing old ifcfg file: $cfg"
    rm -f "$cfg"
fi

### =========================
### Update resolv.conf
### =========================
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
search vgs.com
nameserver 192.168.253.151
EOF
echo "Updated /etc/resolv.conf"

### =========================
### Set hostname from /etc/hosts or hostnamectl
### =========================
hostname_from_hosts=$(awk -v ip="$ip_addr" '$1==ip {print $2}' /etc/hosts)
if [ -n "$hostname_from_hosts" ]; then
    echo "Setting hostname to: $hostname_from_hosts"
    hostnamectl set-hostname "$hostname_from_hosts"
else
    echo "No hostname found in /etc/hosts for $ip_addr. Using hostname -f"
    fqdn=$(hostname -f)
    if ! grep -q "$fqdn" /etc/hosts; then
        echo "Adding entry to /etc/hosts: $ip_addr $fqdn"
        echo "$ip_addr $fqdn" >> /etc/hosts
    fi
    hostnamectl set-hostname "$fqdn"
fi

### =========================
### Check if NM connection exists
### =========================
existing_con=$(nmcli -t -f NAME,DEVICE con show | grep ":${iface}" | cut -d: -f1)

if [ -z "$existing_con" ]; then
    echo "No NetworkManager connection found → Creating new profile"
    nmcli con add type ethernet ifname "$iface" con-name "$profilename" \
        ipv4.method manual \
        ipv4.addresses "$ip_addr/$cidr" \
        ipv4.gateway "$gateway" \
        ipv4.dns "192.168.253.151" \
        ipv4.dns-search "vgs.com" \
        connection.autoconnect yes
else
    echo "NetworkManager connection exists: $existing_con"
    echo "Renaming → $profilename"
    nmcli con modify "$existing_con" connection.id "$profilename"

    ### Update existing connection with proper settings
    nmcli con modify "$profilename" \
        ipv4.method manual \
        ipv4.addresses "$ip_addr/$cidr" \
        ipv4.gateway "$gateway" \
        ipv4.dns "192.168.253.151" \
        ipv4.dns-search "vgs.com" \
        connection.autoconnect yes
fi

### =========================
### Apply the connection
### =========================
nmcli con up "$profilename" || nmcli con reload

### =========================
### Restart NetworkManager to ensure changes take effect
### =========================
systemctl restart NetworkManager

echo "✔ Configuration applied successfully."
echo "✔ Network profile: $profilename"
echo "✔ Hostname: $(hostname -f)"
echo "✔ IP: $ip_addr"
