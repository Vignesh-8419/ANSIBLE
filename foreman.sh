#!/bin/bash
set -e

# -------------------------------
# CONFIGURATION
# -------------------------------
REPO_MOUNT="//192.168.31.87/ISO"
MOUNT_POINT="/var/www/html/repo"
USERNAME="vigne"
PASSWORD="Vigneshv12$"
SKIP_PATCH=false
RUN_ONLY=""

DOMAIN="vgs.com"
REVERSE_ZONE="253.168.192.in-addr.arpa"
NAMED_CONF="/etc/named.conf"
ZONE_DIR="/var/named"
JAVA_PATH="/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.412.b08-1.el7_9.x86_64/bin"
MODULE_PATH="/etc/puppetlabs/code/environments/production/modules/java_ks"

# -------------------------------
# STEP 1: Mount ISO Share (Always Required)
# -------------------------------
echo "📦 Mounting ISO share..."
mkdir -p "$MOUNT_POINT"
if ! findmnt -rno TARGET "$MOUNT_POINT" | grep -q "$MOUNT_POINT"; then
  mount -t cifs "$REPO_MOUNT" "$MOUNT_POINT" \
    -o username="$USERNAME",password="$PASSWORD",rw,dir_mode=0777,file_mode=0777,vers=3.0
  findmnt "$MOUNT_POINT" || { echo "❌ Mount failed."; exit 1; }
else
  echo "⏭️ ISO share already mounted. Skipping."
fi

# -------------------------------
# STEP 2: Clean and Configure YUM Repositories (Always)
# -------------------------------
echo "🧹 Clearing existing YUM repo files..."
rm -f /etc/yum.repos.d/*.repo

echo "📝 Creating base.repo..."
cat <<EOF > /etc/yum.repos.d/base.repo
[baseos]
name=CentOS Base Repo
baseurl=file://$MOUNT_POINT/centos
enabled=1
gpgcheck=0
EOF

echo "📝 Creating patch.repo..."
cat <<EOF > /etc/yum.repos.d/patch.repo
[patch]
name=CentOS Patch Repo
baseurl=file://$MOUNT_POINT/installed_rhel7
enabled=1
gpgcheck=0
EOF

echo "📝 Creating foreman.repo..."
cat <<EOF > /etc/yum.repos.d/foreman.repo
[foreman]
name=CentOS Foreman Repo
baseurl=file://$MOUNT_POINT/installed_rhel7
enabled=1
gpgcheck=0
EOF

echo "📝 Creating puppet.repo..."
cat <<EOF > /etc/yum.repos.d/puppet.repo
[puppet]
name=Puppet 7 Repository
baseurl=file://$MOUNT_POINT/puppet7
enabled=1
gpgcheck=0
EOF

echo "📝 Creating vault.repo..."
cat <<EOF > /etc/yum.repos.d/vault.repo
[base]
name=CentOS Vault Base
baseurl=http://vault.centos.org/7.9.2009/os/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS Vault Updates
baseurl=http://vault.centos.org/7.9.2009/updates/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS Vault Extras
baseurl=http://vault.centos.org/7.9.2009/extras/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

echo "🧠 Installing SSH PASS..."
yum install sshpass -y


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

# -------------------------------
# STEP 7: Configure Foreman Proxies (TFTP, DNS, DHCP)
# -------------------------------
echo "🛠️ Installing DHCP and TFTP services..."
yum install -y dhcp-server dhcp tftp-server 

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
  --foreman-proxy-dns-server "192.168.253.151" \
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
  
firewall-cmd --add-service=dhcp --permanent
firewall-cmd --add-service=tftp --permanent
firewall-cmd --add-port=8140/tcp --permanent
firewall-cmd --reload

echo "✅ Foreman proxy services configured successfully."
