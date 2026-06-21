#!/bin/bash

# Define Colors safely using octal escapes
RED='\x1b[0;31m'
GREEN='\x1b[0;32m'
YELLOW='\x1b[0;33m'
BLUE='\x1b[0;34m'
NC='\x1b[0m' # No Color

# Print Header Function
print_header() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}         SYSTEM CONFIGURATION WIZARD              ${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run this script as root or using sudo.${NC}"
    exit 1
fi

print_header

# Target interface hardcoded as per your requirement
INTERFACE="ens192"
CONFIG_FILE="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE"

# ------------------------------------------
# USER PROMPTS
# ------------------------------------------
read -p "$(echo -e ${YELLOW}"Please provide the hostname: "${NC})" NEW_HOSTNAME
read -p "$(echo -e ${YELLOW}"Please provide IP address with netmask (e.g., 192.168.253.151/24): "${NC})" FULL_IP_CIDR
read -p "$(echo -e ${YELLOW}"Please provide gateway (e.g., 192.168.253.2): "${NC})" GATEWAY
read -p "$(echo -e ${YELLOW}"Please provide dns server (e.g., 192.168.253.1): "${NC})" DNS_SERVER

# Extract pure IP address and Subnet Prefix (e.g., 24) from CIDR
JUST_IP=$(echo "$FULL_IP_CIDR" | cut -d'/' -f1)
PREFIX=$(echo "$FULL_IP_CIDR" | cut -s -d'/' -f2)

# Default to prefix 24 if user forgot to provide the slash notation
if [ -z "$PREFIX" ]; then
    PREFIX="24"
fi

print_header

# ------------------------------------------
# STEP 1: Set Hostname & /etc/hosts Entry
# ------------------------------------------
echo -e "${YELLOW}[Step 1] Setting hostname to: $NEW_HOSTNAME${NC}"
hostnamectl set-hostname "$NEW_HOSTNAME"

if [ $? -eq 0 ] && [ "$(hostnamectl --static)" = "$NEW_HOSTNAME" ]; then
    echo "Updating /etc/hosts file..."
    
    # Remove any existing lines containing the new hostname to prevent duplicates
    sed -i "/ $NEW_HOSTNAME$/d" /etc/hosts
    
    # Append the new IP and Hostname mapping
    echo "$JUST_IP $NEW_HOSTNAME" >> /etc/hosts
    
    # Verify the host entry exists
    if grep -q "$NEW_HOSTNAME" /etc/hosts; then
        echo -e "${GREEN}✔ Step 1 Success: Hostname set and /etc/hosts updated.${NC}\n"
    else
        echo -e "${RED}❌ Step 1 Failed: Hostname set, but failed to update /etc/hosts. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Step 1 Failed: Could not set hostname. Exiting.${NC}"
    exit 1
fi

# ------------------------------------------
# STEP 2: Configure Network via ifcfg-ens192
# ------------------------------------------
echo -e "${YELLOW}[Step 2] Configuring network interface: $INTERFACE via network-scripts${NC}"

# Backup existing configuration if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up existing configuration to ${CONFIG_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
fi

# Write fresh configuration block to the file (including domain)
cat << EOF > "$CONFIG_FILE"
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=none
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=no
NAME=$INTERFACE
DEVICE=$INTERFACE
ONBOOT=yes
IPADDR=$JUST_IP
PREFIX=$PREFIX
GATEWAY=$GATEWAY
DNS1=$DNS_SERVER
DOMAIN=vgs.com
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✔ Step 2 Success: Configuration written to $CONFIG_FILE with domain.${NC}"
    echo "Changes will take full effect after the reboot."
else
    echo -e "${RED}❌ Step 2 Failed: Could not write to $CONFIG_FILE. Exiting.${NC}"
    exit 1
fi

# ------------------------------------------
# STEP 3: Disable SELinux
# ------------------------------------------
echo -e "${YELLOW}[Step 3] Disabling SELinux...${NC}"

SELINUX_CONFIG="/etc/selinux/config"

if [ -f "$SELINUX_CONFIG" ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$SELINUX_CONFIG"
    
    if grep -q "^SELINUX=disabled" "$SELINUX_CONFIG"; then
        echo -e "${GREEN}✔ Step 3 Success: SELinux set to disabled in configuration.${NC}\n"
    else
        echo -e "${RED}❌ Step 3 Failed: Failed to modify SELinux config file. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Step 3 Failed: Configuration file $SELINUX_CONFIG not found. Exiting.${NC}"
    exit 1
fi

# ------------------------------------------
# REBOOT
# ------------------------------------------
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}All steps completed successfully!${NC}"
echo -e "${YELLOW}Rebooting the system in 5 seconds... Press Ctrl+C to cancel.${NC}"
echo -e "${BLUE}==================================================${NC}"

sleep 5
reboot
