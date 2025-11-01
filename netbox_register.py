#!/usr/bin/env python3
import socket
import pynetbox
import netifaces
import subprocess

# ============================
# 🔧 NETBOX CONFIGURATION
# ============================
NETBOX_URL = "http://192.168.253.134"
NETBOX_TOKEN = "ee63f94d72c6c10a5b4e2cab4edbea9af0f18ac0"

SITE_ID = 1             # Predefined site ID (e.g., VGS)
ROLE_NAME = "Server"
DEVICE_TYPE_NAME = "Generic Server"
MANUFACTURER_NAME = "Generic"
TAG_NAME = "auto-register"

# ============================
# ⚙️ AUTO-DETECT HOST DETAILS
# ============================

hostname = socket.gethostname()

def get_primary_interface():
    route_output = subprocess.check_output("ip route | grep default", shell=True).decode()
    return route_output.split("dev")[1].split()[0].strip()

primary_iface = get_primary_interface()
mac_address = netifaces.ifaddresses(primary_iface)[netifaces.AF_LINK][0]['addr']
ip_address = netifaces.ifaddresses(primary_iface)[netifaces.AF_INET][0]['addr'] + "/24"

# ============================
# 🚀 PUSH TO NETBOX
# ============================
nb = pynetbox.api(NETBOX_URL, token=NETBOX_TOKEN)

# Ensure tag exists
tag = nb.extras.tags.get(name=TAG_NAME)
if not tag:
    tag = nb.extras.tags.create({
        "name": TAG_NAME,
        "slug": TAG_NAME.lower().replace(" ", "-")
    })

# Ensure manufacturer exists
manufacturer = nb.dcim.manufacturers.get(name=MANUFACTURER_NAME)
if not manufacturer:
    manufacturer = nb.dcim.manufacturers.create({
        "name": MANUFACTURER_NAME,
        "slug": MANUFACTURER_NAME.lower().replace(" ", "-")
    })

# Ensure device type exists
device_type = nb.dcim.device_types.get(model=DEVICE_TYPE_NAME)
if not device_type:
    device_type = nb.dcim.device_types.create({
        "model": DEVICE_TYPE_NAME,
        "slug": DEVICE_TYPE_NAME.lower().replace(" ", "-"),
        "manufacturer": manufacturer.id
    })

# Ensure device role exists
device_role = nb.dcim.device_roles.get(name=ROLE_NAME)
if not device_role:
    device_role = nb.dcim.device_roles.create({
        "name": ROLE_NAME,
        "slug": ROLE_NAME.lower().replace(" ", "-"),
        "color": "ff0000"
    })

# Check if device already exists
device = nb.dcim.devices.get(name=hostname, site_id=SITE_ID)
if not device:
    device = nb.dcim.devices.create({
        "name": hostname,
        "role": device_role.id,
        "device_type": device_type.id,
        "site": SITE_ID,
        "status": "active",
        "tags": [tag.id]
    })
    print(f"✅ Created device: {hostname}")

    # Create interface
    interface = nb.dcim.interfaces.create({
        "device": device.id,
        "name": primary_iface,
        "type": "1000base-t",
        "mac_address": mac_address
    })
    print(f"✅ Added interface: {primary_iface} ({mac_address})")

    # Assign IP address
    ip = nb.ipam.ip_addresses.create({
        "address": ip_address,
        "status": "active",
        "assigned_object_type": "dcim.interface",
        "assigned_object_id": interface.id
    })
    print(f"✅ Assigned IP: {ip_address} to {primary_iface}")

    print("\n🎉 Server auto-registered successfully in NetBox!")
else:
    print(f"ℹ️ Device '{hostname}' already exists in site {SITE_ID}. Skipping creation.")
