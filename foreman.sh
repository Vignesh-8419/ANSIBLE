#!/bin/bash
set -e

# -------------------------------
# CONFIGURATION
# -------------------------------
MOUNT_POINT="http-server-01.vgs.com/repo"
#USERNAME="vigne"
#PASSWORD="Vigneshv12$"
SKIP_PATCH=false
RUN_ONLY=""

DOMAIN="vgs.com"
JAVA_PATH="/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.412.b08-1.el7_9.x86_64/bin"
MODULE_PATH="/etc/puppetlabs/code/environments/production/modules/java_ks"

# -------------------------------
# STEP 1: Mount ISO Share (Always Required)
# -------------------------------
#echo "📦 Mounting ISO share..."
#mkdir -p "$MOUNT_POINT"
#if ! findmnt -rno TARGET "$MOUNT_POINT" | grep -q "$MOUNT_POINT"; then
#  mount -t cifs "$REPO_MOUNT" "$MOUNT_POINT" \
#    -o username="$USERNAME",password="$PASSWORD",rw,dir_mode=0777,file_mode=0777,vers=3.0
#  findmnt "$MOUNT_POINT" || { echo "❌ Mount failed."; exit 1; }
#else
#  echo "⏭️ ISO share already mounted. Skipping."
#fi

# -------------------------------
# STEP 2: Clean and Configure YUM Repositories (Always)
# -------------------------------
echo "🧹 Clearing existing YUM repo files..."
rm -f /etc/yum.repos.d/*.repo

echo "Check if yum-complete-transaction is pending"
yum-complete-transaction --cleanup-only --quiet --skip-broken

echo "Run yum-complete-transaction if pending"
yum-complete-transaction -y

echo "📝 Creating base.repo..."
cat <<EOF > /etc/yum.repos.d/base.repo
[baseos]
name=CentOS Base Repo
baseurl=http://$MOUNT_POINT/centos
enabled=1
gpgcheck=0

[mesa]
name=Local Mesa Repo
baseurl=http://http-server-01.vgs.com/repo/mesa
enabled=1
gpgcheck=0
priority=1

[gtk]
name=Local GTK Repo
baseurl=http://http-server-01.vgs.com/repo/gtk
enabled=1
gpgcheck=0
priority=1
EOF
yum install -y gtk2 gtk3 mesa-libEGL* tomcat* ruby* apache* rpm-build*

echo "📝 Creating patch.repo..."
cat <<EOF > /etc/yum.repos.d/patch.repo
[patch]
name=CentOS Patch Repo
baseurl=http://$MOUNT_POINT/installed_rhel7
enabled=1
gpgcheck=0
EOF

echo "📝 Creating foreman.repo..."
cat <<EOF > /etc/yum.repos.d/foreman.repo
[foreman]
name=CentOS Foreman Repo
baseurl=http://$MOUNT_POINT/installed_rhel7
enabled=1
gpgcheck=0
EOF

echo "📝 Creating puppet.repo..."
cat <<EOF > /etc/yum.repos.d/puppet.repo
[puppet7]
name=Puppet 7 Repository EL7
baseurl=https://yum.puppet.com/puppet7/el/7/x86_64/
enabled=1
gpgcheck=0
EOF

echo "📝 Creating vault.repo..."
cat <<EOF > /etc/yum.repos.d/vault.repo
[base]
name=CentOS Vault Base
baseurl=https://vault.centos.org/centos/7/os/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS Vault Updates
baseurl=https://vault.centos.org/centos/7/updates/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS Vault Extras
baseurl=https://vault.centos.org/centos/7/extras/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

echo "🧠 Installing SSH PASS..."
yum install -y sshpass*


# -------------------------------
# STEP 3: Install BIND Configure  DNS (Conditional)
# -------------------------------
echo "🔍 Checking DNS resolution for current server..."
if nslookup "$(hostname)" &>/dev/null; then
  echo "✅ DNS resolution is working. Skipping DNS configuration steps."
else
  echo "⚠️ DNS resolution failed. Proceeding with DNS setup..."

  echo "🌐 Configuring DNS resolver..."
  echo "nameserver $DNS_IP" > /etc/resolv.conf
  nslookup google.com || echo "⚠️ DNS resolution failed"

fi

yum install -y bind*

# -------------------------------
# STEP 4: Install Java & Foreman Stack
# -------------------------------
echo "☕ Installing Java and Foreman stack..."
yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
yum install -y puppetserver katello foreman-installer
yum install -y rh-redis5-redis
sudo systemctl enable rh-redis5-redis
sudo systemctl start rh-redis5-redis

echo "🔧 Setting JAVA path..."
export PATH="$JAVA_PATH:$PATH"

# -------------------------------
# STEP 5: Puppet Module Setup
# -------------------------------
echo "📁 Checking puppetlabs-java_ks module..."
if [ -d "$MODULE_PATH" ]; then
  echo "🧹 Removing existing java_ks module..."
  rm -rf "$MODULE_PATH"
fi

echo "📦 Installing puppetlabs-java_ks module..."
/opt/puppetlabs/bin/puppet module install puppetlabs-java_ks --force

echo "🔗 Linking module for Foreman installer..."
mkdir -p /usr/share/foreman-installer/modules
ln -sf "$MODULE_PATH" /usr/share/foreman-installer/modules/java_ks
# -------------------------------
# STEP 4.5: Make your script resilient, add a check before running the installer
# -------------------------------
if yum history list &>/dev/null; then
  echo "✅ Yum history is healthy."
else
  echo "⚠️ Yum history is corrupted. Resetting..."
  mv /var/lib/yum/history /var/lib/yum/history.bak
  yum clean all
  rpm --rebuilddb
fi

# -------------------------------
# STEP 5.1: Pre-task for foreman installer
# -------------------------------

echo "🔧 Updating /etc/hosts entries ..."

NEW_HOSTNAME=$(hostname -s)
JUST_IP=$(hostname -I | awk '{print $1}')

echo "Updating /etc/hosts file..."

sed -i "/${NEW_HOSTNAME}/d" /etc/hosts
echo "${JUST_IP} ${NEW_HOSTNAME}.vgs.com ${NEW_HOSTNAME}" >> /etc/hosts

grep "${NEW_HOSTNAME}.vgs.com" /etc/hosts

yum makecache

# -------------------------------
# STEP 6: Run Foreman Installer
# -------------------------------
if ! systemctl is-active foreman &>/dev/null; then
  echo "🚀 Running Foreman installer with Katello scenario..."
  foreman-installer --scenario katello
  firewall-cmd --add-service=http --permanent
  firewall-cmd --add-service=https --permanent
  firewall-cmd --reload
else
  echo "⏭️ Foreman already running."
fi

echo "📦 Relocating Pulp storage to /home..."

if mountpoint -q /var/lib/pulp; then
    echo "✅ Pulp is already using a bind mount. Skipping relocation."

else
    foreman-maintain service stop

    mkdir -p /home/pulp

    if [ ! -d /var/lib/pulp.old ]; then
        echo "📁 Copying Pulp data..."
        yum install -y rsync
        rsync -aHAX --numeric-ids /var/lib/pulp/ /home/pulp/

        echo "📁 Backing up original Pulp directory..."
        mv /var/lib/pulp /var/lib/pulp.old

        mkdir -p /var/lib/pulp
    fi

    mount --bind /home/pulp /var/lib/pulp

    grep -q "^/home/pulp[[:space:]]\+/var/lib/pulp" /etc/fstab || \
        echo "/home/pulp /var/lib/pulp none bind 0 0" >> /etc/fstab

    restorecon -RF /home/pulp >/dev/null 2>&1 || true
    restorecon -RF /var/lib/pulp >/dev/null 2>&1 || true

    systemctl daemon-reload

    echo "🧪 Verifying Pulp bind mount..."

    mountpoint -q /var/lib/pulp || {
        echo "❌ /var/lib/pulp is not a mount point."
        exit 1
    }

    touch /var/lib/pulp/.migration-test

    if [ ! -f /home/pulp/.migration-test ]; then
        echo "❌ Bind mount verification failed."
        exit 1
    fi

    rm -f /var/lib/pulp/.migration-test

    echo "✅ Bind mount verification successful."

    echo "🚀 Starting Foreman services..."
    foreman-maintain service start

    echo "🧹 Removing old Pulp directory..."
    rm -rf /var/lib/pulp.old
fi

echo "✅ Pulp storage relocated."

# -------------------------------
# STEP 7: Configure Foreman Proxies (TFTP, DNS, DHCP)
# -------------------------------
echo "🛠️ Installing DHCP and TFTP services..."
yum install -y dhcp-server dhcp tftp-server

# -------------------------------------------------------
# Temporarily mount EFI partitions for Foreman TFTP setup
# -------------------------------------------------------

echo "📁 Temporarily mounting EFI partitions..."

mkdir -p /boot/efi
mkdir -p /boot/efi2

mountpoint -q /boot/efi || mount /dev/sda1 /boot/efi
mountpoint -q /boot/efi2 || mount /dev/sdb1 /boot/efi2

echo "Verifying EFI contents..."

ls -l /boot/efi/EFI/
ls -l /boot/efi2/EFI/

# Ensure shim exists where Foreman expects it
if [ ! -f /boot/efi/EFI/centos/shimx64.efi ]; then
    echo "❌ /boot/efi/EFI/centos/shimx64.efi not found"
    exit 1
fi

if [ ! -f /boot/efi2/EFI/centos/shimx64.efi ]; then
    echo "❌ /boot/efi2/EFI/centos/shimx64.efi not found"
    exit 1
fi

echo "✅ EFI partitions mounted successfully."

echo "📦 Configuring Foreman TFTP proxy..."
foreman-installer --scenario katello \
  --foreman-proxy-tftp true \
  --foreman-proxy-tftp-managed true \
  --foreman-proxy-tftp-root /var/lib/tftpboot \
  --foreman-proxy-tftp-servername "cent-07-01.vgs.com"


echo "🔐 Generating DNSSEC key for Foreman proxy..."
dnssec-keygen -a HMAC-SHA512 -b 512 -n USER foreman-proxy
mv Kforeman-proxy*.private /etc/foreman-proxy/dns.key
chown foreman-proxy:foreman-proxy /etc/foreman-proxy/dns.key
chmod 600 /etc/foreman-proxy/dns.key

echo "🌐 Configuring Foreman DNS proxy..."
foreman-installer --scenario katello \
  --foreman-proxy-dns true \
  --foreman-proxy-dns-managed false \
  --foreman-proxy-dns-provider nsupdate \
  --foreman-proxy-dns-server "192.168.253.1" \
  --foreman-proxy-dns-forwarders="8.8.8.8,8.8.4.4" \
  --foreman-proxy-keyfile /etc/foreman-proxy/dns.key

echo "📡 Configuring Foreman DHCP proxy..."
foreman-installer --scenario katello \
  --foreman-proxy-dhcp true \
  --foreman-proxy-dhcp-managed true \
  --foreman-proxy-dhcp-server "cent-07-01.vgs.com" \
  --foreman-proxy-dhcp-range "" \
  --foreman-proxy-dhcp-gateway "192.168.253.2" \
  --foreman-proxy-dhcp-nameservers "cent-07-01.vgs.com" \
  --foreman-proxy-dhcp-config "/etc/dhcp/dhcpd.conf" \
  --foreman-proxy-dhcp-leases "/var/lib/dhcpd/dhcpd.leases"

# -------------------------------------------------------
# Unmount temporary EFI partitions
# -------------------------------------------------------

echo "🧹 Unmounting temporary EFI partitions..."

sync

mountpoint -q /boot/efi2 && umount /boot/efi2
mountpoint -q /boot/efi && umount /boot/efi

rmdir /boot/efi2 2>/dev/null || true
rmdir /boot/efi 2>/dev/null || true

echo "✅ Temporary EFI mounts removed."
  
firewall-cmd --add-service=dhcp --permanent
firewall-cmd --add-service=tftp --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-port=8140/tcp --permanent
firewall-cmd --reload


mkdir -p /var/lib/tftpboot/centos

curl -L -o /var/lib/tftpboot/centos/initrd.img \
http://http-server-01/repo/centos/isolinux/initrd.img

curl -L -o /var/lib/tftpboot/centos/vmlinuz \
http://http-server-01/repo/centos/isolinux/vmlinuz

chown -R foreman-proxy:root /var/lib/tftpboot/centos
chmod 644 /var/lib/tftpboot/centos/*

echo "✅ Foreman proxy services configured successfully."
