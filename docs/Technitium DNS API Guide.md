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


# Technitium DNS Forwarding Configuration

1. Verified that the Windows client was using the Jio router (192.168.31.1) as its primary DNS server.
2. Confirmed that Technitium DNS Server (192.168.253.1) could resolve internal zone records such as ansible-server-01.vgs.com.
3. Identified that external DNS queries (e.g., google.com) were failing with "Server failed" errors.
4. Configured upstream DNS forwarders in Technitium DNS Server:

   * 192.168.31.1
   * 8.8.8.8
   * 1.1.1.1
5. Verified that recursion was enabled using "Allow Recursion Only For Private Networks".
6. Tested external DNS resolution and found that DNS-over-UDP forwarding was not working correctly.
7. Changed the Forwarder Protocol from DNS-over-UDP to DNS-over-TCP.
8. Successfully resolved external domains (google.com, github.com, etc.) through Technitium DNS Server.
9. Confirmed that both internal (vgs.com) and external Internet DNS queries were resolving correctly.
10. Final DNS architecture uses Technitium DNS Server (192.168.253.1) as the primary DNS resolver for both lab and Internet name resolution.
