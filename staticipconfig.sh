#!/bin/bash

# Detect primary interface
iface=$(ip route | awk '/default/ {print $5}' | head -n1)

# Detect current IP, netmask, and gateway
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

# Backup original config
cfg_file="/etc/sysconfig/network-scripts/ifcfg-${iface}"
cp "$cfg_file" "${cfg_file}.bak"

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

# Make resolv.conf writable and update
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
search vgs.com
nameserver 192.168.253.151
EOF

# Restart network
systemctl restart network
