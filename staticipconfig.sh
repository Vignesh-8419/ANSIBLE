#!/bin/bash

### Detect primary interface (default route)
iface=$(ip route | awk '/default/ {print $5}' | head -n1)

if [ -z "$iface" ]; then
  echo "ERROR: No default interface detected"
  exit 1
fi

echo "Detected interface: $iface"

### Detect ALTNAME (if present)
altname=$(ip -o link show "$iface" | grep -o 'altname [^ ]*' | awk '{print $2}')
if [ -n "$altname" ]; then
  profilename="$altname"
else
  profilename="$iface"
fi

echo "NetworkManager profile name will be: $profilename"

### Detect IP, CIDR, Gateway
ip_full=$(ip -4 addr show "$iface" | awk '/inet /{print $2}')
ip_addr=${ip_full%/*}
cidr=${ip_full#*/}
gateway=$(ip route | awk '/default/ {print $3}')

### CIDR → Netmask conversion
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

### Write ifcfg file
cfg="/etc/sysconfig/network-scripts/ifcfg-${iface}"

cat > "$cfg" <<EOF
DEVICE=$iface
BOOTPROTO=none
ONBOOT=yes
IPADDR=$ip_addr
NETMASK=$netmask
GATEWAY=$gateway
DNS1=192.168.253.151
DOMAIN=vgs.com
IPV6INIT=yes
EOF

echo "Updated: $cfg"

### Update resolv.conf
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
search vgs.com
nameserver 192.168.253.151
EOF

echo "Updated /etc/resolv.conf"

### Set hostname from /etc/hosts
hostname_from_hosts=$(awk -v ip="$ip_addr" '$1==ip {print $2}' /etc/hosts)
if [ -n "$hostname_from_hosts" ]; then
    echo "Setting hostname to: $hostname_from_hosts"
    hostnamectl set-hostname "$hostname_from_hosts"
else
    echo "No hostname found in /etc/hosts for $ip_addr. Skipping hostname change."
fi

### Check if NM connection exists
existing_con=$(nmcli -t -f NAME,DEVICE con show | grep ":${iface}" | cut -d: -f1)

if [ -z "$existing_con" ]; then
    echo "No NetworkManager connection found → Creating new profile"
    nmcli con add type ethernet ifname "$iface" con-name "$profilename" \
        ipv4.method manual \
        ipv4.addresses "$ip_addr/$cidr" \
        ipv4.gateway "$gateway" \
        ipv4.dns "192.168.253.151" \
        ipv4.dns-search "vgs.com"
else
    echo "NetworkManager connection exists: $existing_con"
    echo "Renaming → $profilename"
    nmcli con modify "$existing_con" connection.id "$profilename"

    ### Also fix DNS inside NM so resolv.conf won't be overwritten
    nmcli con modify "$profilename" ipv4.method manual \
        ipv4.addresses "$ip_addr/$cidr" \
        ipv4.gateway "$gateway" \
        ipv4.dns "192.168.253.151" \
        ipv4.dns-search "vgs.com"
fi

### Apply the connection
nmcli con up "$profilename" || nmcli con reload

### Ensure default route via 192.168.253.2
if ! ip route show | grep -q "default via 192.168.253.2"; then
    echo "Default route via 192.168.253.2 not found → adding"
    ip route add default via 192.168.253.2 dev "$iface"
else
    echo "Default route via 192.168.253.2 already exists"
fi

echo "✔ Configuration applied successfully."
echo "✔ Network profile: $profilename"
echo "✔ Hostname: $(hostname)"
