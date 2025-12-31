#!/bin/bash

### =========================
### Detect first ens* interface
### =========================
iface=$(ip -o link show | awk -F: '/ ens/ {print $2; exit}' | tr -d ' ')

if [ -z "$iface" ]; then
    echo "ERROR: No ens* interface found. Exiting."
    exit 1
fi

echo "Detected interface: $iface"

### =========================
### Detect IP, CIDR
### =========================
ip_full=$(ip -4 addr show "$iface" | awk '/inet /{print $2}')
if [ -z "$ip_full" ]; then
    echo "ERROR: No IPv4 address found on $iface. Exiting."
    exit 1
fi

ip_addr=${ip_full%/*}
cidr=${ip_full#*/}

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
### Default Gateway
### =========================
gateway="192.168.253.2"
# Replace default route to avoid duplicates
ip route replace default via $gateway dev "$iface"
echo "Default route set via $gateway dev $iface"

### =========================
### Detect ALTNAME for NetworkManager profile
### =========================
altname=$(ip -o link show "$iface" | grep -o 'altname [^ ]*' | awk '{print $2}')
if [ -n "$altname" ]; then
    profilename="$altname"
else
    profilename="$iface"
fi
echo "NetworkManager profile name: $profilename"

### =========================
### Remove old ifcfg file
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
### Set hostname and /etc/hosts entry
### =========================
fqdn=$(hostname -f)
if ! grep -q "$fqdn" /etc/hosts; then
    echo "Adding entry to /etc/hosts: $ip_addr $fqdn"
    echo "$ip_addr $fqdn" >> /etc/hosts
fi
hostnamectl set-hostname "$fqdn"
echo "Hostname set to: $fqdn"

### =========================
### NetworkManager connection
### =========================
existing_con=$(nmcli -t -f NAME,DEVICE con show | grep ":${iface}" | cut -d: -f1)

if [ -z "$existing_con" ]; then
    echo "Creating new NetworkManager connection: $profilename"
    nmcli con add type ethernet ifname "$iface" con-name "$profilename" \
        ipv4.method manual \
        ipv4.addresses "$ip_addr/$cidr" \
        ipv4.gateway "$gateway" \
        ipv4.dns "192.168.253.151" \
        ipv4.dns-search "vgs.com" \
        connection.autoconnect yes
else
    echo "Modifying existing connection: $existing_con → $profilename"
    nmcli con modify "$existing_con" connection.id "$profilename"
    nmcli con modify "$profilename" \
        ipv4.method manual \
        ipv4.addresses "$ip_addr/$cidr" \
        ipv4.gateway "$gateway" \
        ipv4.dns "192.168.253.151" \
        ipv4.dns-search "vgs.com" \
        connection.autoconnect yes
fi

# Ensure NetworkManager ignores auto DNS
nmcli con modify "$profilename" ipv4.ignore-auto-dns yes


sed -i 's/^ONBOOT=.*/ONBOOT=yes/' /etc/sysconfig/network-scripts/$existing_con

# Apply connection
nmcli con up "$profilename" || nmcli con reload


# Restart NetworkManager
systemctl restart NetworkManager

### =========================
### Success message and reboot
### =========================
echo "✔ Configuration applied successfully."
echo "✔ Network profile: $profilename"
echo "✔ Hostname: $(hostname -f)"
echo "✔ IP: $ip_addr"
echo "✔ Default Gateway: $gateway"

echo "Server will reboot in 10 seconds..."
sleep 10
reboot
