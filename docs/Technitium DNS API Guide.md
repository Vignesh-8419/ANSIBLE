# Technitium DNS API Guide

## Configuration

```bash
DNS_SERVER="192.168.253.1"
TOKEN="14759e1e000567381175d02ef3e137d2847e6dd637e5a74bcdb726e24dabaac7"
```

---

# Create Forward Zone

Zone Name:

```text
vgs.com
```

Command:

```bash
curl "http://192.168.253.1/api/zones/create?token=${TOKEN}&zone=vgs.com&type=Primary"
```

---

# Create Reverse Zone

Zone Name:

```text
253.168.192.in-addr.arpa
```

Command:

```bash
curl "http://192.168.253.1/api/zones/create?token=${TOKEN}&zone=253.168.192.in-addr.arpa&type=Primary"
```

---

# Create A Record

Hostname:

```text
cent-07-01.vgs.com
```

IP Address:

```text
192.168.253.131
```

Command:

```bash
curl "http://192.168.253.1/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=false"
```

Expected Record:

```text
cent-07-01.vgs.com    A    192.168.253.131
```

---

# Create PTR Record

Reverse Zone:

```text
253.168.192.in-addr.arpa
```

PTR Record:

```text
131.253.168.192.in-addr.arpa
```

Command:

```bash
curl "http://192.168.253.1/api/zones/records/add?token=${TOKEN}&zone=253.168.192.in-addr.arpa&domain=131.253.168.192.in-addr.arpa&type=PTR&ttl=3600&ptrName=cent-07-01.vgs.com"
```

Expected Record:

```text
131.253.168.192.in-addr.arpa    PTR    cent-07-01.vgs.com
```

---

# Create A + PTR Automatically

Command:

```bash
curl "http://192.168.253.1/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=true&createPtrZone=true"
```

Expected Output:

```text
Forward Record:
cent-07-01.vgs.com    A    192.168.253.131

Reverse Record:
131.253.168.192.in-addr.arpa    PTR    cent-07-01.vgs.com
```

---

# List DNS Zones

```bash
curl "http://192.168.253.1/api/zones/list?token=${TOKEN}"
```

---

# View Records in Forward Zone

```bash
curl "http://192.168.253.1/api/zones/records/get?token=${TOKEN}&domain=vgs.com"
```

---

# View Records in Reverse Zone

```bash
curl "http://192.168.253.1/api/zones/records/get?token=${TOKEN}&domain=253.168.192.in-addr.arpa"
```

---

# Verify DNS Resolution

## Forward Lookup

```bash
nslookup cent-07-01.vgs.com 192.168.253.1
```

Expected:

```text
Name:    cent-07-01.vgs.com
Address: 192.168.253.131
```

## Reverse Lookup

```bash
nslookup 192.168.253.131 192.168.253.1
```

Expected:

```text
131.253.168.192.in-addr.arpa
name = cent-07-01.vgs.com
```

---

# Full Example Workflow

```bash
# Create Forward Zone
curl "http://192.168.253.1/api/zones/create?token=${TOKEN}&zone=vgs.com&type=Primary"

# Create Reverse Zone
curl "http://192.168.253.1/api/zones/create?token=${TOKEN}&zone=253.168.192.in-addr.arpa&type=Primary"

# Create Host Record
curl "http://192.168.253.1/api/zones/records/add?token=${TOKEN}&zone=vgs.com&domain=cent-07-01.vgs.com&type=A&ttl=3600&ipAddress=192.168.253.131&ptr=true"

# Verify
nslookup cent-07-01.vgs.com 192.168.253.1
nslookup 192.168.253.131 192.168.253.1
```
