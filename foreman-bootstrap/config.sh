#!/bin/bash
###############################################################################
# Foreman / Katello Bootstrap Configuration
###############################################################################

#############################
# Foreman
#############################

FOREMAN_URL="https://cent-07-01.vgs.com"

FOREMAN_USER="admin"
FOREMAN_PASSWORD="zqs977dXzqfEvTML"

#############################
# Organization
#############################

ORG="Default Organization"
LOCATION="Default Location"

#############################
# Repository Server
#############################

REPO_SERVER="192.168.253.136"
HTTP_SERVER="http://192.168.253.136"

REPO_URL="${HTTP_SERVER}/repo"

#############################
# Installation Media
#############################

CENTOS_MEDIA_NAME="CentOS 7 Remote"
CENTOS_MEDIA_URL="${REPO_URL}/centos"

ROCKY_MEDIA_NAME="Rocky 8 Remote"
ROCKY_MEDIA_URL="${REPO_URL}/rocky8"

#############################
# Operating Systems
#############################

CENTOS_OS_NAME="CentOSLinux"
CENTOS_MAJOR="7"

ROCKY_OS_NAME="RockyLinux"
ROCKY_MAJOR="8"
ROCKY_MINOR="10"

ARCH="x86_64"
OS_FAMILY="Redhat"
PARTITION_TABLE="Kickstart default"

#############################
# PXE Templates
#############################

CENTOS_TEMPLATE="PXEGrub2 CentOS UEFI Static Kickstart"
ROCKY_TEMPLATE="PXEGrub2 RockyOS UEFI Static Kickstart"

#############################
# Domains
#############################

DOMAIN="vgs.com"

#############################
# Network
#############################

NETWORK="192.168.253.0"
NETMASK="255.255.255.0"

GATEWAY="192.168.253.2"
DNS_SERVER="192.168.253.1"

RANGE_FROM="192.168.253.10"
RANGE_TO="192.168.253.240"

MTU="1500"

#############################
# Subnets
#############################

CENTOS_SUBNET="vgs-subnet-centos"
ROCKY_SUBNET="vgs-subnet-rockyos"

#############################
# Smart Proxies
#############################

CENTOS_PROXY="cent-07-01.vgs.com"
ROCKY_PROXY="cent-07-02.vgs.com"

#############################
# Host Groups
#############################

CENTOS_HOSTGROUP="VGS HOSTS CENTOS 7"
ROCKY_HOSTGROUP="VGS HOSTS ROCKY 8"

PXE_LOADER="Grub2 UEFI"

#############################
# Katello Products
#############################

CENTOS_PRODUCT="CentOS 7"
ROCKY_PRODUCT="Rocky Linux 8"

#############################
# Repositories
#############################

CENTOS_BASEOS_REPO="CentOS-07-BaseOS"
CENTOS_UPDATES_REPO="CentOS-07-Updates"

ROCKY_BASEOS_REPO="Rocky-08-BaseOS"
ROCKY_APPSTREAM_REPO="Rocky-08-AppStream"
ROCKY_INSTALLED_REPO="Rocky-08-RHEL-Installed"

#############################
# Repository URLs
#############################

CENTOS_BASEOS_URL="${REPO_URL}/centos/"
CENTOS_UPDATES_URL="${REPO_URL}/installed_rhel7/"

ROCKY_BASEOS_URL="${REPO_URL}/rocky8/BaseOS"
ROCKY_APPSTREAM_URL="${REPO_URL}/rocky8/Appstream"
ROCKY_INSTALLED_URL="${REPO_URL}/installed_rhel8"

#############################
# Content Views
#############################

CENTOS_CV="CentOS7-CV"
ROCKY_CV="Rocky8-CV"

CV_DESCRIPTION="Initial Publish"

#############################
# Lifecycle
#############################

LIFECYCLE="Library"

#############################
# Activation Keys
#############################

CENTOS_KEY="centos7-prod-key"
ROCKY_KEY="rocky8-prod-key"

#############################
# Content Source
#############################

CONTENT_SOURCE="cent-07-01.vgs.com"

#############################
# Hammer Command
#############################

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"

#############################
# CURL
#############################

CURL="curl -ks"

#############################
# Logging
#############################

LOG_DIR="$(pwd)/logs"
LOG_FILE="${LOG_DIR}/bootstrap.log"

#############################
# Colors
#############################

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
NC="\033[0m"

#############################
# Script Version
#############################

VERSION="1.0"

#############################
# End
#############################
