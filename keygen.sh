#!/bin/bash

dnf install -y sshpass

# Ensure 137 has a keypair
sshpass -p "Root@123" ssh -o StrictHostKeyChecking=no root@192.168.253.137 "
  mkdir -p /root/.ssh
  [ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa -q <<< y
  cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/authorized_keys
"

# Fetch 137's public key
sshpass -p "Root@123" scp -o StrictHostKeyChecking=no root@192.168.253.137:/root/.ssh/id_rsa.pub /tmp/id_rsa_137.pub

# Push 137's key into 138 and 139
for NODE in 192.168.253.138 192.168.253.139; do
  sshpass -p "Root@123" ssh -o StrictHostKeyChecking=no root@$NODE "
    mkdir -p /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
  "
  sshpass -p "Root@123" scp -o StrictHostKeyChecking=no /tmp/id_rsa_137.pub root@$NODE:/root/.ssh/
  sshpass -p "Root@123" ssh -o StrictHostKeyChecking=no root@$NODE "
    cat /root/.ssh/id_rsa_137.pub >> /root/.ssh/authorized_keys
    rm -f /root/.ssh/id_rsa_137.pub
    chmod 600 /root/.ssh/authorized_keys
  "
done

echo "✅ SSH trust established: 137 can now SSH into 138 and 139 without password."
