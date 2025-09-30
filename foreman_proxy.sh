#!/bin/bash
set -e

# -------------------------------
# CONFIGURATION
# -------------------------------
REPO_MOUNT="//192.168.31.87/ISO"
MOUNT_POINT="/var/www/html/repo"
USERNAME="vigne"
PASSWORD="Vigneshv12\$"
FOREMAN_PROXY="cent-07-02.vgs.com"
CERT_PATH="/root/${FOREMAN_PROXY}-certs.tar"
INSTALLER_OUTPUT="/tmp/proxy_installer_output.txt"


# -------------------------------
# STEP 1: Generate Certificates
# -------------------------------
echo "🔐 Generating certificates for Smart Proxy: $FOREMAN_PROXY..."
foreman-proxy-certs-generate \
  --foreman-proxy-fqdn "$FOREMAN_PROXY" \
  --certs-tar "$CERT_PATH" | tee "$INSTALLER_OUTPUT"

echo "✅ Certificate archive created at $CERT_PATH"

OAUTH_KEY=$(grep -- '--foreman-proxy-oauth-consumer-key' "$INSTALLER_OUTPUT" | awk -F'"' '{print $2}')
OAUTH_SECRET=$(grep -- '--foreman-proxy-oauth-consumer-secret' "$INSTALLER_OUTPUT" | awk -F'"' '{print $2}')

if [[ -z "$OAUTH_KEY" || -z "$OAUTH_SECRET" ]]; then
  echo "❌ OAuth credentials not found. Aborting."
  exit 1
fi

echo "🔑 Extracted OAuth Key: $OAUTH_KEY"
echo "🔐 Extracted OAuth Secret: $OAUTH_SECRET"


# -------------------------------
# STEP 2: Generate Remote Installer Script
# -------------------------------
cat <<EOF > /tmp/remote_installer.sh
#!/bin/bash
set -e

rm -f /etc/yum.repos.d/*.repo

echo "🔍 Checking if ISO share is mounted..."
mkdir -p /var/www/html/repo
if ! findmnt -rn /var/www/html/repo > /dev/null; then
  echo "🔗 ISO share not mounted. Attempting to mount..."
  mount -t cifs $REPO_MOUNT /var/www/html/repo \\
    -o username=$USERNAME,password=$PASSWORD,rw,dir_mode=0777,file_mode=0777,vers=3.0 || {
      echo "❌ Mount failed. Check credentials, network, or CIFS support."
      exit 1
  }
  echo "✅ Mount successful:"
  findmnt /var/www/html/repo
else
  echo "✅ ISO share is already mounted:"
  findmnt /var/www/html/repo
fi

# YUM repo setup
cat <<REPO > /etc/yum.repos.d/local.repo
[local-patch]
name=Local CentOS Patch Repo
baseurl=file:///var/www/html/repo/installed_rhel7
enabled=1
gpgcheck=0

[puppet]
name=Puppet 7 Repository
baseurl=file:///var/www/html/repo/puppet7
enabled=1
gpgcheck=0
REPO

cat <<REPO > /etc/yum.repos.d/foreman-online.repo
[foreman-new-repo]
name=Foreman New Repo
baseurl=https://yum-backend.repo-rpm01.osuosl.theforeman.org/releases/3.0/el7/x86_64/
enabled=1
gpgcheck=0

[foreman-add-repo]
name=Foreman Add Repo
baseurl=https://yum.theforeman.org/plugins/3.2/el7/x86_64/
enabled=1
gpgcheck=0
REPO

cat <<REPO > /etc/yum.repos.d/vault.repo
[vaultbase]
name=CentOS Vault Base
baseurl=http://vault.centos.org/7.9.2009/os/x86_64/
enabled=1
gpgcheck=0

[updates]
name=CentOS Vault Updates
baseurl=http://vault.centos.org/7.9.2009/updates/x86_64/
enabled=1
gpgcheck=0

[extras]
name=CentOS Vault Extras
baseurl=http://vault.centos.org/7.9.2009/extras/x86_64/
enabled=1
gpgcheck=0
REPO

yum install -y foreman foreman-proxy puppetserver --skip-broken
yum install -y foreman-installer*

echo "📂 Extracting Smart Proxy certificates..."
mkdir -p /etc/foreman-proxy
tar -xf /root/${FOREMAN_PROXY}-certs.tar -C /etc/foreman-proxy

echo "🌐 Detecting active network interface..."
INTERFACE=\$(ip route get 8.8.8.8 | awk '{print \$5; exit}')
if [[ -z "\$INTERFACE" ]]; then
  INTERFACE=\$(ip -o -4 addr show | awk '{print \$2}' | head -1)
fi
echo "🌐 Using network interface: \$INTERFACE"

# Firewall setup
firewall-cmd --add-service=dhcp --permanent
firewall-cmd --add-service=tftp --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-port=9090/tcp --permanent
firewall-cmd --add-port=443/tcp --permanent
firewall-cmd --reload

echo "🚀 Running Foreman Proxy installer..."
foreman-installer \\
  --scenario foreman-proxy-content \\
  --certs-tar-file "/root/${FOREMAN_PROXY}-certs.tar" \\
  --foreman-proxy-register-in-foreman "true" \\
  --foreman-proxy-foreman-base-url "https://cent-07-01.vgs.com" \\
  --foreman-proxy-trusted-hosts "cent-07-01.vgs.com" \\
  --foreman-proxy-trusted-hosts "${FOREMAN_PROXY}" \\
  --foreman-proxy-oauth-consumer-key "${OAUTH_KEY}" \\
  --foreman-proxy-oauth-consumer-secret "${OAUTH_SECRET}" \\
  --foreman-proxy-dhcp true \\
  --foreman-proxy-dhcp-interface "\$INTERFACE" \\
  --foreman-proxy-dns true \\
  --foreman-proxy-dns-interface "\$INTERFACE" \\
  --foreman-proxy-tftp true \\
  --foreman-proxy-tftp-servername "${FOREMAN_PROXY}"

echo "✅ Smart Proxy installation completed."
EOF


# -------------------------------
# STEP 3: Transfer Remote Script and Certificates
# -------------------------------
echo "🚀 Transferring installer script and certificates to $FOREMAN_PROXY..."
sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no /tmp/remote_installer.sh root@$FOREMAN_PROXY:/root/
sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no "$CERT_PATH" root@$FOREMAN_PROXY:/root/


# -------------------------------
# STEP 4: Execute Remote Script
# -------------------------------
echo "🚀 Executing remote installer on $FOREMAN_PROXY..."
sshpass -p 'Root@123' ssh -o StrictHostKeyChecking=no root@$FOREMAN_PROXY "bash /root/remote_installer.sh"
