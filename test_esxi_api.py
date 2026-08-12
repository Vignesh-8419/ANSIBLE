from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim
import ssl

ESXI_HOST = "192.168.253.128"
ESXI_USER = "admin"
ESXI_PASSWORD = "Root@123"

context = ssl._create_unverified_context()

si = SmartConnect(
    host=ESXI_HOST,
    user=ESXI_USER,
    pwd=ESXI_PASSWORD,
    sslContext=context
)

print("Successfully connected to ESXi:", ESXI_HOST)

content = si.RetrieveContent()

for datacenter in content.rootFolder.childEntity:
    print("Datacenter:", datacenter.name)

    for vm in datacenter.vmFolder.childEntity:
        print(
            "VM:",
            vm.name,
            "| Power:",
            vm.runtime.powerState
        )

Disconnect(si)
print("Disconnected from ESXi")
