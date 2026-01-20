#!/bin/bash

echo "installing GIT"

sudo yum install -y git

echo "installed GIT"

echo "downloading git"

git clone --depth 1 https://github.com/Vignesh-8419/pihole Pi-hole

cd Pi-hole/automated\ install/

echo "Config PIHOLE file"


echo "enabling firewall"

firewall-cmd --add-service=dns --permanent

firewall-cmd --add-service=http --permanent

firewall-cmd --add-service=https --permanent

firewall-cmd --reload

echo "enabled firewall"

echo "Configured PIHOLE file"

setenforce 0

echo "config selinux"

export PIHOLE_SELINUX=true

echo "configured selinux"

bash basic-install.sh

#vi /etc/pihole/pihole.toml
#[webserver]
  # 'r' tells FTL to redirect HTTP traffic to the first available HTTPS port
#  port = "80r,443os,[::]:80r,[::]:443os"
#systemctl restart pihole-FTL

# 1. Generate a new key and certificate for your specific domain
#openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
#  -keyout /etc/pihole/tls.key -out /etc/pihole/tls.crt \
#  -subj "/CN=dns-server-01.vgs.com" \
#  -addext "subjectAltName=DNS:dns-server-01.vgs.com,DNS:pi.hole"

# 2. Combine them into the tls.pem file that pihole-FTL uses
#cat /etc/pihole/tls.key /etc/pihole/tls.crt > /etc/pihole/tls.pem

# 3. Fix permissions
#chown pihole:pihole /etc/pihole/tls.*
#chmod 644 /etc/pihole/tls.crt /etc/pihole/tls.pem
#chmod 600 /etc/pihole/tls.key

# 4. Restart Pi-hole FTL
#systemctl restart pihole-FTL

# Add permissions for web traffic
#firewall-cmd --permanent --add-service=http
#firewall-cmd --permanent --add-service=https

# Reload to apply changes
#firewall-cmd --reload
