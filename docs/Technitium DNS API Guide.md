# PowerShell Environment Variables

## Set DNS Server

```powershell
$env:DNS_SERVER="192.168.253.1"
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

Expected Output:

```text
192.168.253.1
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

# Get Foword Zone Records

```powershell
$r = Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/get?token=$($env:TOKEN)&domain=vgs.com"

$r.response.records | Format-List *
```

# Get Reverse Zone Records

```powershell
$r = Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/get?token=$($env:TOKEN)&domain=253.168.192.in-addr.arpa"

$r.response.records | Format-List *
```

# DNS Manager API Commands (Git Bash)

## Set Environment Variables

```bash
export DNS_SERVER="192.168.253.1"
export TOKEN="14759e1e000567381175d02ef3e137d2847e6dd637e5a74bcdb726e24dabaac7"
```

---

## Verify Variables

```bash
echo $DNS_SERVER
echo $TOKEN
```

### Expected Output

```text
192.168.253.1
14759e1e000567381175d02ef3e137d2847e6dd637e5a74bcdb726e24dabaac7
```

---

## Create Forward Zone

```bash
curl "http://${DNS_SERVER}/api/zones/create?token=${TOKEN}&zone=vgs.com&type=Primary"
```

---

## Create Reverse Zone

```bash
curl "http://${DNS_SERVER}/api/zones/create?token=${TOKEN}&zone=253.168.192.in-addr.arpa&type=Primary"
```

---

## Create A Record

```bash
curl "http://${DNS_SERVER}/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=false"
```

---

## Create PTR Record

```bash
curl "http://${DNS_SERVER}/api/zones/records/add?token=${TOKEN}&zone=253.168.192.in-addr.arpa&domain=131.253.168.192.in-addr.arpa&type=PTR&ttl=3600&ptrName=cent-07-01.vgs.com"
```

---

## Create A + PTR Automatically

```bash
curl "http://${DNS_SERVER}/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=true&createPtrZone=true"
```

---

## List Zones

### Raw Output

```bash
curl -s "http://${DNS_SERVER}/api/zones/list?token=${TOKEN}"
```

### Pretty JSON Output (jq Required)

```bash
curl -s "http://${DNS_SERVER}/api/zones/list?token=${TOKEN}" | jq
```

### Show Zone Names Only

```bash
curl -s "http://${DNS_SERVER}/api/zones/list?token=${TOKEN}" | jq -r '.response.zones[] | "\(.name) \(.type)"'
```

---

## Get Forward Zone Records

### Raw Output

```bash
curl -s "http://${DNS_SERVER}/api/zones/records/get?token=${TOKEN}&domain=vgs.com"
```

### Pretty JSON Output

```bash
curl -s "http://${DNS_SERVER}/api/zones/records/get?token=${TOKEN}&domain=vgs.com" | jq
```

---

## Get Reverse Zone Records

### Raw Output

```bash
curl -s "http://${DNS_SERVER}/api/zones/records/get?token=${TOKEN}&domain=253.168.192.in-addr.arpa"
```

### Pretty JSON Output

```bash
curl -s "http://${DNS_SERVER}/api/zones/records/get?token=${TOKEN}&domain=253.168.192.in-addr.arpa" | jq
```

---

## DNS Verification

### Forward Lookup

```bash
nslookup cent-07-01.vgs.com 192.168.253.1
```

### Reverse Lookup

```bash
nslookup 192.168.253.131 192.168.253.1
```

---

## Connectivity Verification

### HTTP Check

```bash
curl "http://${DNS_SERVER}"
```

### Ping Check

```bash
ping -n 4 ${DNS_SERVER}
```

---

## Example: Create New Host Record

```bash
curl "http://${DNS_SERVER}/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=test-server-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.39&ptr=true&createPtrZone=true"
```

### Verify

```bash
nslookup test-server-01.vgs.com 192.168.253.1
```

Expected Result:

```text
Name:    test-server-01.vgs.com
Address: 192.168.253.39
```


# Steps to Configure Technitium DNS for Internal and Internet Resolution

### 1. Verify Internal DNS Resolution

Open Command Prompt and test:

```cmd
nslookup ansible-server-01.vgs.com 192.168.253.1
```

Confirm that internal DNS records resolve correctly.

---

### 2. Verify External DNS Resolution

Test Internet DNS resolution:

```cmd
nslookup google.com 192.168.253.1
```

Issue observed:

```text
*** Server failed
```

---

### 3. Open Technitium DNS Web Console

Access:

```text
http://192.168.253.1
```

Navigate to:

```text
Settings → Proxy & Forwarders
```

---

### 4. Configure Forwarders

Add the following DNS servers under **Forwarders**:

```text
192.168.31.1
8.8.8.8
1.1.1.1
```

---

### 5. Verify Recursion Settings

Navigate to:

```text
Settings → Recursion
```

Ensure the following option is selected:

```text
Allow Recursion Only For Private Networks
```

---

### 6. Change Forwarder Protocol

Navigate to:

```text
Settings → Proxy & Forwarders
```

Change:

```text
DNS-over-UDP (default)
```

to:

```text
DNS-over-TCP
```

Click **Save Settings**.

---

### 7. Test DNS Resolution from Technitium

Go to:

```text
DNS Client
```

Query:

```text
google.com
```

Confirm that valid IP addresses are returned.

---

### 8. Test from Windows Client

Run:

```cmd
nslookup google.com 192.168.253.1
nslookup github.com 192.168.253.1
nslookup ansible-server-01.vgs.com 192.168.253.1
```

Verify that both Internet and internal domains resolve successfully.

---

### 9. Configure Windows to Use Technitium DNS

Open PowerShell as Administrator:

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses 192.168.253.1
```

Flush DNS cache:

```cmd
ipconfig /flushdns
```

---

### 10. Final Verification

```cmd
nslookup google.com
nslookup ansible-server-01.vgs.com
```

Expected Result:

* Internal domains (*.vgs.com) resolve correctly.
* Internet domains (google.com, github.com, redhat.com, etc.) resolve correctly.
* Technitium DNS Server (192.168.253.1) acts as the primary DNS server for the lab environment.
