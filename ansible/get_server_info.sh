#!/bin/bash

USER="root"
PASS="Root@123"
SERVER_FILE="servers.txt"
PARALLEL=20  # number of servers to run in parallel

if [ ! -f "$SERVER_FILE" ]; then
  echo "Error: $SERVER_FILE not found!"
  exit 1
fi

run_server() {
  SERVER="$1"

  sshpass -p "$PASS" ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$SERVER bash -s << 'EOF'
echo "-----------------------------------------"
echo "SERVER: $(hostname -I | awk "{print \$1}")"
echo

echo "Hostname:"
hostname
echo

echo "OS Release:"
grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
echo

echo "Kernel Version:"
uname -r
echo

echo "Interface | IP Address | MAC Address"
echo "------------------------------------"

# Only print interfaces starting with 'ens' (or 'eth' if needed)
ip -o -4 addr show up | awk '{print $2, $4}' | grep -E '^(ens|eth)' | while read iface ip; do
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null)
    printf "%s | %s | %s\n" "$iface" "$ip" "$mac"
done

echo "-----------------------------------------"
EOF
}

export -f run_server
export USER PASS

cat "$SERVER_FILE" | xargs -n 1 -P "$PARALLEL" bash -c 'run_server "$@"' _
