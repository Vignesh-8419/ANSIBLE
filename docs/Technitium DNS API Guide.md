# Technitium DNS API Commands (Updated for Web Console Port 5380)

> **Note**
>
> * **Technitium DNS Service (DNS):** `192.168.253.1:53`
> * **Technitium Web Console & REST API:** `http://192.168.253.1:5380`
> * **Nginx Repository:** `http://192.168.253.136`

---

# PowerShell Environment Variables

## Set DNS Server

```powershell
$env:DNS_SERVER="192.168.253.1:5380"
```

## Set API Token

```powershell
$env:TOKEN="19089ed0460d3e8cf0b15d5c1aad1826b8bc89c67279a153bd423e84a6d49bd7"
```

## Verify Variables

```powershell
$env:DNS_SERVER
$env:TOKEN
```

Expected Output

```text
192.168.253.1:5380
14759e1e000567381175d02ef3e137d2847e6dd637e5a74bcdb726e24dabaac7
```

---

# Create Forward Zone

```powershell
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/create?token=$($env:TOKEN)&zone=vgs.com&type=Primary"
```

---

# Create Reverse Zone

```powershell
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/create?token=$($env:TOKEN)&zone=253.168.192.in-addr.arpa&type=Primary"
```

---

# Create A Record

```powershell
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/add?token=$($env:TOKEN)&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=false"
```

---

# Create PTR Record

```powershell
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/add?token=$($env:TOKEN)&zone=253.168.192.in-addr.arpa&domain=131.253.168.192.in-addr.arpa&type=PTR&ttl=3600&ptrName=cent-07-01.vgs.com"
```

---

# Create A + PTR Automatically

```powershell
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/add?token=$($env:TOKEN)&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=true&createPtrZone=true"
```

---

# List Zones

```powershell
$r = Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/list?token=$($env:TOKEN)"

$r.response.zones | Format-Table name,type
```

---

# Get Forward Zone Records

```powershell
$r = Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/get?token=$($env:TOKEN)&domain=vgs.com"

$r.response.records | Format-List *
```

---

# Get Reverse Zone Records

```powershell
$r = Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/get?token=$($env:TOKEN)&domain=253.168.192.in-addr.arpa"

$r.response.records | Format-List *
```

---

# Git Bash Environment Variables

## Set Environment Variables

```bash
export DNS_SERVER="192.168.253.1:5380"
export TOKEN="14759e1e000567381175d02ef3e137d2847e6dd637e5a74bcdb726e24dabaac7"
```

---

## Verify Variables

```bash
echo $DNS_SERVER
echo $TOKEN
```

Expected Output

```text
192.168.253.1:5380
14759e1e000567381175d02ef3e137d2847e6dd637e5a74bcdb726e24dabaac7
```

---

# Create Forward Zone

```bash
curl "http://${DNS_SERVER}/api/zones/create?token=${TOKEN}&zone=vgs.com&type=Primary"
```

---

# Create Reverse Zone

```bash
curl "http://${DNS_SERVER}/api/zones/create?token=${TOKEN}&zone=253.168.192.in-addr.arpa&type=Primary"
```

---

# Create A Record

```bash
curl "http://${DNS_SERVER}/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=false"
```

---

# Create PTR Record

```bash
curl "http://${DNS_SERVER}/api/zones/records/add?token=${TOKEN}&zone=253.168.192.in-addr.arpa&domain=131.253.168.192.in-addr.arpa&type=PTR&ttl=3600&ptrName=cent-07-01.vgs.com"
```

---

# Create A + PTR Automatically

```bash
curl "http://${DNS_SERVER}/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=true&createPtrZone=true"
```

---

# List Zones

```bash
curl -s "http://${DNS_SERVER}/api/zones/list?token=${TOKEN}" | jq
```

---

# Get Forward Zone Records

```bash
curl -s "http://${DNS_SERVER}/api/zones/records/get?token=${TOKEN}&domain=vgs.com" | jq
```

---

# Get Reverse Zone Records

```bash
curl -s "http://${DNS_SERVER}/api/zones/records/get?token=${TOKEN}&domain=253.168.192.in-addr.arpa" | jq
```

---

# Connectivity Verification

## Verify Web Console / REST API

```bash
curl "http://${DNS_SERVER}"
```

Expected URL:

```text
http://192.168.253.1:5380
```

---

# DNS Verification (No Changes)

> DNS queries continue to use **port 53**.

## Forward Lookup

```bash
nslookup cent-07-01.vgs.com 192.168.253.1
```

## Reverse Lookup

```bash
nslookup 192.168.253.131 192.168.253.1
```

## Internet Lookup

```bash
nslookup google.com 192.168.253.1
```

---

# Configure Technitium DNS for Internet Resolution

## Open Web Console

```text
http://192.168.253.1:5380
```

Navigate to:

```text
Settings → Proxy & Forwarders
```

Configure Forwarders:

```text
192.168.31.1
8.8.8.8
1.1.1.1
```

Navigate to:

```text
Settings → Recursion
```

Select:

```text
Allow Recursion Only For Private Networks
```

Navigate to:

```text
Settings → Proxy & Forwarders
```

Change protocol:

```text
DNS-over-UDP
```

to

```text
DNS-over-TCP
```

Click **Save Settings**.

---

# Configure Windows DNS Client

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses 127.0.0.1
```

```powershell
ipconfig /flushdns
```


Flush DNS cache:

```cmd
ipconfig /flushdns
```

---

# Final Verification

```cmd
nslookup google.com
nslookup github.com
nslookup ansible-server-01.vgs.com
```

Expected Result:

* Internal `*.vgs.com` records resolve correctly.
* Internet domains resolve successfully.
* DNS queries use `192.168.253.1:53`.
* Technitium Web Console and REST API are available at `http://192.168.253.1:5380`.

# Windows Firewall Configuration for Technitium DNS (Port 5380)

## Purpose

Allow remote systems such as AWX, Ansible, Foreman, and Linux servers to access the Technitium DNS Web API running on TCP port **5380**.

---

# 1. Verify Technitium is Listening

Open **PowerShell** as **Administrator** and run:

```powershell
netstat -ano | findstr :5380
```

Expected output:

```text
TCP    0.0.0.0:5380     0.0.0.0:0      LISTENING
TCP    [::]:5380        [::]:0         LISTENING
```

This confirms that Technitium DNS is listening on all network interfaces.

---

# 2. Check Existing Firewall Rule

Run:

```powershell
Get-NetFirewallRule -Enabled True |
Get-NetFirewallPortFilter |
Where-Object {$_.LocalPort -eq "5380"}
```

If no rule is returned, create one.

---

# 3. Create Windows Firewall Rule

Open **PowerShell** as **Administrator** and execute:

```powershell
New-NetFirewallRule `
    -DisplayName "Technitium DNS Web API" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5380 `
    -Action Allow
```

Expected output:

```text
Name                          : {GUID}
DisplayName                   : Technitium DNS Web API
Enabled                       : True
Direction                     : Inbound
Action                        : Allow
```

---

# 4. Verify Firewall Rule

```powershell
Get-NetFirewallRule -DisplayName "Technitium DNS Web API"
```

or

```powershell
Get-NetFirewallRule |
Where-Object DisplayName -like "*Technitium*"
```

---

# 5. Test Port from Windows

```powershell
Test-NetConnection 127.0.0.1 -Port 5380
```

Expected:

```text
TcpTestSucceeded : True
```

Also test the configured IP:

```powershell
Test-NetConnection 192.168.253.1 -Port 5380
```

Expected:

```text
TcpTestSucceeded : True
```

---

# 6. Test from Linux / AWX

From the Ansible or AWX server:

```bash
curl -v http://192.168.253.1:5380
```

or

```bash
nc -vz 192.168.253.1 5380
```

Successful output indicates that the Windows firewall is allowing inbound connections.

---

# 7. Verify API Access

```bash
curl "http://192.168.253.1:5380/api/zones/list?token=<API_TOKEN>"
```


# Technitium DNS Fix and VMware VMnet0, VMnet1, VMnet8 Network Configuration

## 1. Lab Environment

| Component | Configuration |
|---|---|
| Windows host / Repo server | `192.168.253.136` |
| Technitium DNS server | `192.168.253.1` |
| Rocky Linux server | `192.168.253.145/24` |
| VMware NAT gateway | `192.168.253.2` |
| DNS port | `53` UDP/TCP |
| Technitium web console | `http://192.168.253.1:5380` |
| DNS domain | `vgs.com` |
| Rocky Linux interface | `ens33` |
| VMware VM network mode | NAT |

## 2. VMware Virtual Network Overview

VMware Workstation commonly uses these virtual networks:

| Virtual Network | Typical Mode | Purpose |
|---|---|---|
| VMnet0 | Bridged | Connects VMs to the physical network |
| VMnet1 | Host-only | Private communication between the host and VMs |
| VMnet8 | NAT | Allows VMs to access external networks through the host |

**Important:** These are VMware defaults. Verify the actual mode, subnet, and gateway in **VMware Workstation → Edit → Virtual Network Editor**. Do not assume the defaults match the current lab configuration.

### VMnet0 — Bridged Network

- Connects VMs to a physical network through a selected host network adapter.
- VMs normally obtain addresses from the physical network's DHCP server or use configured static addresses.
- The Windows host's VMnet0 adapter may not be involved in the same way as a host-only adapter.

### VMnet1 — Host-only Network

- Creates a private network between the host and connected VMs.
- External access is not provided by default.
- Useful for isolated lab networks.

### VMnet8 — NAT Network

- Allows VMs to access external networks through VMware NAT.
- Uses a configured virtual subnet and NAT gateway.
- The VM's IP address, subnet, and gateway must match the actual VMnet8 configuration.

## 3. Current Windows Network Details

Run in PowerShell:

    Get-NetIPConfiguration -InterfaceAlias "VMware Network Adapter VMnet0"

    Get-NetIPConfiguration -InterfaceAlias "VMware Network Adapter VMnet8"

The observed configuration for the VMware virtual adapters included:

### VMnet0

    IPv4Address:
      192.168.253.136
      192.168.253.1

    IPv4DefaultGateway:
      192.168.253.2

    DNSServer:
      192.168.253.1
      192.168.31.1

### VMnet8

    IPv4Address:
      192.168.253.136
      192.168.253.1

    IPv4DefaultGateway:
      192.168.253.2

    DNSServer:
      192.168.253.1

**Important:** Both adapters were reported with the same addresses in the command outputs. This is unusual and should be verified in Windows and VMware Virtual Network Editor. Do not remove or change either address until the actual adapter configuration has been confirmed. The repo server uses `192.168.253.136`, and Technitium DNS uses `192.168.253.1`.

### Inspect all VMware adapters

    Get-NetAdapter |
        Where-Object { $_.Name -like "*VMware*" } |
        Format-Table Name, Status, MacAddress, LinkSpeed

    Get-NetIPConfiguration |
        Where-Object { $_.InterfaceAlias -like "*VMware*" }

## 4. Verify VMware NAT Service

Run in PowerShell:

    Get-Service *VMware* |
        Format-Table Name, Status, DisplayName

The observed result showed:

    VMware NAT Service    Running

Check the VMnet8 adapter:

    Get-NetAdapter -Name "VMware Network Adapter VMnet8" |
        Format-List Name, Status, MacAddress, LinkSpeed

The observed result showed the adapter was `Up`.

## 5. Verify Rocky Linux Network Configuration

Run on `ansible-server-01`:

    ip -4 addr show ens33
    ip route
    ip neigh show

Observed Rocky Linux configuration:

    ens33: 192.168.253.145/24

    default via 192.168.253.2 dev ens33

    192.168.253.0/24 dev ens33

Test the VMware NAT gateway:

    ping -c 4 -W 2 192.168.253.2

The gateway responded successfully with no packet loss.

## 6. Original DNS Problem

DNS queries to Technitium initially timed out:

    dig @192.168.253.1 google.com +time=3 +tries=1

The initial error was:

    ;; connection timed out; no servers could be reached

Initial connectivity tests showed:

| Test | Result |
|---|---|
| Ping `192.168.253.2` | Successful |
| Ping `192.168.253.1` | No response |
| TCP port `5380` | Reachable |
| TCP port `53` | Timed out |
| DNS query to `192.168.253.1` | Timed out |

Ping failure alone does not prove DNS is unavailable because ICMP may be blocked independently.

## 7. Check Technitium DNS Listener

Run in PowerShell as Administrator:

    Get-NetUDPEndpoint -LocalPort 53 |
        Format-Table LocalAddress, LocalPort, OwningProcess

    Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue |
        Format-Table LocalAddress, LocalPort, State, OwningProcess

    Get-Process -Id 2420,4204 -ErrorAction SilentlyContinue |
        Format-Table Id, ProcessName, Path

Observed listeners included:

- PID `2420`: Technitium `DnsService.exe`
- PID `4204`: `svchost.exe`, also bound to UDP port 53

The second listener may warrant further investigation, but it was not confirmed as the root cause.

## 8. DNS Fix — Windows Firewall Rules

Open **PowerShell as Administrator**.

### Allow UDP port 53

    New-NetFirewallRule `
        -DisplayName "Technitium DNS - UDP 53 - Lab" `
        -Direction Inbound `
        -Protocol UDP `
        -LocalAddress 192.168.253.1 `
        -LocalPort 53 `
        -RemoteAddress 192.168.253.0/24 `
        -Action Allow `
        -Profile Any

### Allow TCP port 53

    New-NetFirewallRule `
        -DisplayName "Technitium DNS - TCP 53 - Lab" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalAddress 192.168.253.1 `
        -LocalPort 53 `
        -RemoteAddress 192.168.253.0/24 `
        -Action Allow `
        -Profile Any

Both rules were created successfully.

These rules allow inbound DNS traffic from the lab subnet `192.168.253.0/24` to `192.168.253.1`. Keep Windows Firewall enabled.

## 9. Verify DNS Resolution

On Rocky Linux:

    dig @192.168.253.1 google.com +time=3 +tries=1

The query subsequently returned:

    status: NOERROR

    SERVER: 192.168.253.1#53

    ANSWER SECTION:
    google.com.    IN    A    <IP_ADDRESS>

The successful response contained six IPv4 addresses and took approximately `1819 msec`.

Test normal DNS resolution:

    nslookup google.com
    dig google.com

Check resolver settings:

    cat /etc/resolv.conf

Expected configuration:

    nameserver 192.168.253.1
    search vgs.com

Test internal DNS:

    nslookup vgs.com
    dig @192.168.253.1 vgs.com +time=3 +tries=1

The internal zone and requested records must exist in Technitium for the internal lookup to succeed.

## 10. Verify Firewall Rules

Run in PowerShell:

    Get-NetFirewallRule `
        -DisplayName "Technitium DNS - UDP 53 - Lab",
                      "Technitium DNS - TCP 53 - Lab" |
        Format-Table DisplayName, Enabled, Direction, Action, Profile

## 11. Verify Actual VMware Network Mapping

Open **VMware Workstation → Edit → Virtual Network Editor**.

For each network, verify the actual settings:

- **VMnet0:** Confirm whether it is Bridged and which physical adapter it uses.
- **VMnet1:** Confirm whether it is Host-only and note its subnet.
- **VMnet8:** Confirm whether it is NAT and note its subnet and NAT gateway.

For VMnet8, also open **NAT Settings** and check the gateway IP.

The Rocky VM's network adapter should be connected to the virtual network intended for its configured IP and gateway. If it uses NAT, its static IP and gateway must match the actual VMnet8 subnet and NAT gateway.

Do not switch between VMnet0 and VMnet8 blindly. Verify the mappings first, because the current Windows adapter outputs show duplicate IP configurations.

## 12. Final Status

| Item | Status |
|---|---|
| Rocky Linux IP | `192.168.253.145/24` |
| VMware NAT gateway | `192.168.253.2` |
| Technitium DNS | `192.168.253.1` |
| Repo server | `192.168.253.136` |
| VMware NAT Service | Running |
| VMware VMnet8 adapter | Up |
| DNS firewall rules | Created successfully |
| External DNS query | Successful (`NOERROR`) |
| Internal `vgs.com` DNS | Requires record-specific verification |

## 13. Notes

- Keep Windows Firewall enabled.
- Keep the UDP 53 and TCP 53 rules enabled for the lab subnet.
- Do not stop `SharedAccess` or modify the duplicate adapter IP addresses without further diagnosis.
- The successful response included `EDE: 3 (Stale Answer)`. If it continues, investigate Technitium's cache and forwarder behavior.
- If DNS fails again, check the Windows firewall rules, Technitium listener, VMware virtual network mapping, and Rocky Linux resolver configuration.


A JSON response confirms that the Technitium DNS Web API is reachable.

---

# Summary

* Verified Technitium DNS listens on TCP port **5380**.
* Created an inbound Windows Firewall rule allowing TCP **5380**.
* Confirmed firewall rule is enabled.
* Tested local connectivity using `Test-NetConnection`.
* Verified remote access from Linux/AWX using `curl` or `nc`.
* Confirmed the Technitium DNS Web API is accessible over the network.

