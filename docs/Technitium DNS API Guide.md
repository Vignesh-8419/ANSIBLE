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
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/list?token=$($env:TOKEN)"
```

---

# Get Zone Records

```powershell
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/get?token=$($env:TOKEN)&domain=vgs.com"
```

```powershell
Invoke-RestMethod "http://$($env:DNS_SERVER)/api/zones/records/get?token=$($env:TOKEN)&domain=253.168.192.in-addr.arpa"
```
