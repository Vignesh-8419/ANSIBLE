#!/bin/bash

# Detect primary interface (the one with default route)
iface=$(ip route | awk '/default/ {print $5}' | head -n1)

if [ -z "$iface" ]; then
  echo "Error: No default interface detected"
  exit 1
fi

# Detect current IP, CIDR, and gateway
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

# Backup original config if present
cfg_file="/etc/sysconfig/network-scripts/ifcfg-${iface}"
if [ -f "$cfg_file" ]; then
  cp "$cfg_file" "${cfg_file}.bak"
fi

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

# Update resolv.conf
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
search vgs.com
nameserver 192.168.253.151
EOF

# Detect the NetworkManager connection bound to this interface
con_name=$(nmcli -t -f NAME,DEVICE con show | grep ":${iface}" | cut -d: -f1)

if [ -n "$con_name" ] && [ "$con_name" != "$iface" ]; then
  # Normalize connection name to match interface name
  nmcli con modify "$con_name" connection.id "$iface"
fi

# Bring up the connection using interface name
nmcli connection up "$iface"
