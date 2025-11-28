#!/bin/bash

echo "installing GIT"

sudo yum install -y git

echo "installed GIT"

echo "downloading git"

git clone --depth 1 https://github.com/pi-hole/pi-hole.git Pi-hole

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
