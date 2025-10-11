#!/usr/bin/env python3
import socket
import pynetbox
import netifaces
import subprocess

# ============================
# 🔧 NETBOX CONFIGURATION
# ============================
NETBOX_URL = "http://192.168.253.196"
NETBOX_TOKEN = "c4382cd4dcce700700b4a1d73ca5f64c53e475c9"

SITE_ID = 1             # Predefined in NetBox
ROLE_ID = 1             # e.g., Server
DEVICE_TYPE_ID = 1      # e.g., Dell PowerEdge
TAG_NAME = "auto-register"

# ============================
# ⚙️ AUTO-DETECT HOST DETAILS
# ============================

# Get hostname
hostname = socket.gethostname()

# Detect the primary interface (the one with a default route)
def get_primary_interface():
    route_output = subprocess.check_output("ip route | grep default", shell=True).decode()
    return route_output.split("dev")[1].split()[0].strip()

primary_iface = get_primary_interface()

# Get MAC address
mac_address = netifaces.ifaddresses(primary_iface)[netifaces.AF_LINK][0]['addr']

# Get primary IP address (IPv4)
ip_address = netifaces.ifaddresses(primary_iface)[netifaces.AF_INET][0]['addr'] + "/24"

# ============================
# 🚀 PUSH TO NETBOX
# ============================
nb = pynetbox.api(NETBOX_URL, token=NETBOX_TOKEN)

# Ensure the tag exists or create it
tag = nb.extras.tags.get(name=TAG_NAME)
if not tag:
    tag = nb.extras.tags.create({
        "name": TAG_NAME,
        "slug": TAG_NAME.lower().replace(" ", "-")
    })

# Check if device already exists
device = nb.dcim.devices.get(name=hostname, site_id=SITE_ID)
if not device:
    device = nb.dcim.devices.create(
        name=hostname,
        role=ROLE_ID,
        device_type=DEVICE_TYPE_ID,
        site=SITE_ID,
        status="active",
        tags=[{"name": TAG_NAME}]
    )
    print(f"✅ Created device: {hostname}")

    # Create interface with MAC
    interface = nb.dcim.interfaces.create(
        device=device.id,
        name=primary_iface,
        type="1000base-t",
        mac_address=mac_address
    )
    print(f"✅ Added interface: {primary_iface} ({mac_address})")

    # Assign IP address
    ip = nb.ipam.ip_addresses.create(
        address=ip_address,
        status="active",
        assigned_object_type="dcim.interface",
        assigned_object_id=interface.id
    )
    print(f"✅ Assigned IP: {ip_address} to {primary_iface}")

    print("\n🎉 Server auto-registered successfully in NetBox!")
else:
    print(f"ℹ️ Device '{hostname}' already exists in site {SITE_ID}. Skipping creation.")
