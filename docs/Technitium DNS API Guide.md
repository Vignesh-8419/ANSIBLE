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
$env:TOKEN="14759e1e000567381175d02ef3e137d2847e6dd637e5a74bcdb726e24dabaac7"
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
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses 192.168.253.1
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

A JSON response confirms that the Technitium DNS Web API is reachable.

---

# Summary

* Verified Technitium DNS listens on TCP port **5380**.
* Created an inbound Windows Firewall rule allowing TCP **5380**.
* Confirmed firewall rule is enabled.
* Tested local connectivity using `Test-NetConnection`.
* Verified remote access from Linux/AWX using `curl` or `nc`.
* Confirmed the Technitium DNS Web API is accessible over the network.

