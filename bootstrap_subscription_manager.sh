#!/bin/bash
###############################################################################
# Temporary Repository Bootstrap
#
# Supported:
#   - RHEL 7
#   - RHEL 8
#   - RHEL 9.2
#   - RHEL 9.8
#
# Installs subscription-manager using temporary local repositories and then
# removes the temporary repo files.
###############################################################################

set -euo pipefail

REPO_SERVER="192.168.253.136"

# RHEL7 uses a different server name
RHEL7_SERVER="http-server-01"

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[FAIL]\033[0m $*"; exit 1; }

###############################################################################
# Detect OS Version
###############################################################################

if [[ ! -f /etc/os-release ]]; then
    error "/etc/os-release not found."
fi

source /etc/os-release

OS_MAJOR="${VERSION_ID%%.*}"
OS_MINOR="${VERSION_ID#*.}"

info "Detected: ${PRETTY_NAME}"

###############################################################################
# Backup Existing Repositories
###############################################################################

mkdir -p /etc/yum.repos.d/backup

find /etc/yum.repos.d \
    -maxdepth 1 \
    -name "*.repo" \
    -exec mv {} /etc/yum.repos.d/backup/ \;

###############################################################################
# Configure Temporary Repositories
###############################################################################

case "${OS_MAJOR}" in

7)

info "Configuring temporary repositories for RHEL 7"

cat >/etc/yum.repos.d/base.repo <<EOF
[base]
name=Base Repo
baseurl=http://${RHEL7_SERVER}/repo/centos
enabled=1
gpgcheck=0
EOF

cat >/etc/yum.repos.d/patch.repo <<EOF
[patch]
name=Installed Packages
baseurl=http://${RHEL7_SERVER}/repo/installed_rhel7
enabled=1
gpgcheck=0
EOF

;;

8)

info "Configuring temporary repositories for RHEL 8"

cat >/etc/yum.repos.d/rocky8-baseos.repo <<EOF
[rocky8-baseos]
name=Rocky Linux 8 BaseOS
baseurl=http://${REPO_SERVER}/repo/rocky8/BaseOS
enabled=1
gpgcheck=0
EOF

cat >/etc/yum.repos.d/rocky8-appstream.repo <<EOF
[rocky8-appstream]
name=Rocky Linux 8 AppStream
baseurl=http://${REPO_SERVER}/repo/rocky8/Appstream
enabled=1
gpgcheck=0
EOF

cat >/etc/yum.repos.d/rocky8-rhel-installed.repo <<EOF
[rocky8-rhel-installed]
name=Installed Packages
baseurl=http://${REPO_SERVER}/repo/installed_rhel8
enabled=1
gpgcheck=0
EOF

;;

9)

if [[ "${OS_MINOR}" == "2" ]]; then

    REPO_PATH="rocky9.2"

elif [[ "${OS_MINOR}" == "8" ]]; then

    REPO_PATH="rocky9"

else

    error "Unsupported RHEL 9 version: ${VERSION_ID}"

fi

info "Configuring temporary repositories for RHEL ${VERSION_ID}"

cat >/etc/yum.repos.d/rocky9-baseos.repo <<EOF
[rocky9-baseos]
name=Rocky Linux 9 BaseOS
baseurl=http://${REPO_SERVER}/repo/${REPO_PATH}/BaseOS
enabled=1
gpgcheck=0
EOF

cat >/etc/yum.repos.d/rocky9-appstream.repo <<EOF
[rocky9-appstream]
name=Rocky Linux 9 AppStream
baseurl=http://${REPO_SERVER}/repo/${REPO_PATH}/Appstream
enabled=1
gpgcheck=0
EOF

cat >/etc/yum.repos.d/rocky9-rhel-installed.repo <<EOF
[rocky9-rhel-installed]
name=Installed Packages
baseurl=http://${REPO_SERVER}/repo/installed_rhel9
enabled=1
gpgcheck=0
EOF

;;

*)

error "Unsupported operating system version: ${VERSION_ID}"

;;

esac

###############################################################################
# Install subscription-manager
###############################################################################

info "Cleaning repository cache..."

yum clean all

info "Installing subscription-manager..."

yum install -y subscription-manager

###############################################################################
# Cleanup Temporary Repositories
###############################################################################

info "Removing temporary repositories..."

rm -f /etc/yum.repos.d/*.repo

ok "subscription-manager installed successfully."
