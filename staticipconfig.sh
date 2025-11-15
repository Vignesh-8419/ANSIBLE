#!/bin/bash

# Detect primary interface (default route)
iface=$(ip route | awk '/default/ {print $5}' | head -n1)

if [ -z "$iface" ]; then
  echo "Error: No default interface detected"
  exit 1
fi

echo "Detected primary interface: $iface"

# Detect ALTNAME from ip command
altname=$(ip -o link show "$iface" | grep -o 'altname [^ ]*' | awk '{print $2}')

if [ -z "$altname" ]; then
  echo "No altname found — using interface name as profile name"
  profilename="$iface"
else
  echo "Detected ALTNAME: $altname"
  profilename="$altname"
fi

# Detect IP, CIDR, gateway
ip_addr=$(ip -4 addr show "$iface" | awk '/inet / {print $2}' | cut -d/ -f1)
cidr=$(ip -4 addr show "$iface" | awk '/inet / {print $2}' | cut -d/ -f2)
gateway=$(ip route | awk '/default/ {print $3}' | head -n1)

# Convert CIDR to netmask
cidr2mask() {
  local i mask=""
  local full_octets=$(($1/8))
  local remainder=$(($1%8))
  for ((i=0;i<4;i++)); do
    if [ $i -lt $full_octets ]; then
      mask+=255
    elif [ $i -eq $full_octets ]; then
      mask+=$((256 - 2**(8 - remainder)))
    else
      mask+=0
    fi
    [ $i -lt 3 ] && mask+=.
  done
  echo $mask
}
netmask=$(cidr2mask "$cidr")

cfg_file="/etc/sysconfig/network-scripts/ifcfg-${iface}"

# Backup old config
[ -f "$cfg_file" ] && cp "$cfg_file" "${cfg_file}.bak"

# Write static config
cat > "$cfg_file" <<EOF
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

echo "Written static config: $cfg_file"

# Fix resolv.conf
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
search vgs.com
nameserver 192.168.253.151
EOF

echo "Updated resolv.conf"

# Find current NM connection bound to iface
current_con=$(nmcli -t -f NAME,DEVICE con show | grep ":${iface}" | cut -d: -f1)

# Rename connection to ALTNAME (profilename)
if [ -n "$current_con" ]; then
  echo "Renaming connection '$current_con' -> '$profilename'"
  nmcli con modify "$current_con" connection.id "$profilename"
else
  echo "No connection found for $iface, creating new one..."

  nmcli con add type ethernet ifname "$iface" con-name "$profilename" \
    ipv4.method manual ipv4.addresses "$ip_addr/$cidr" ipv4.gateway "$gateway" \
    ipv4.dns "192.168.253.151" ipv4.dns-search "vgs.com"
fi

# Bring connection up
nmcli con up "$profilename"

echo "Network configuration applied successfully."
