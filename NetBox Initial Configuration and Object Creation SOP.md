# NetBox Initial Configuration and Object Creation SOP

![NetBox](https://img.shields.io/badge/NetBox-v4.x-green)
![API](https://img.shields.io/badge/API-Configuration-blue)
![Automation](https://img.shields.io/badge/Automation-cURL-orange)

---

# Overview

This document covers the initial NetBox configuration required before integrating with AWX and automation workflows.

The following objects will be created:

* Site
* Device Role
* Manufacturer
* Device Type
* Tags
* Interface Verification

---

# Environment Details

| Parameter        | Value                       |
| ---------------- | --------------------------- |
| NetBox URL       | https://192.168.253.143     |
| API Endpoint     | https://192.168.253.143/api |
| Authentication   | API Token                   |
| SSL Verification | Disabled (-k)               |

> [!WARNING]
> The examples below use `-k` to bypass SSL certificate validation. This is suitable for lab environments but should be avoided in production.

---

# Step 1 – Verify API Connectivity

## Purpose

Confirm API access and validate authentication.

## Command

```bash
curl -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
https://192.168.253.143/api/dcim/interfaces/?device_id=2
```

## Expected Result

JSON output containing interface information for Device ID 2.

Example:

```json
{
  "count": 2,
  "results": [
    {
      "name": "eth0"
    }
  ]
}
```

---


# Step 2 – Create Device Role

## Purpose

Creates a standard server role.

### Device Role Details

| Property | Value  |
| -------- | ------ |
| Name     | Server |
| Slug     | server |

## Command

```bash
curl -X POST \
-k \
"https://192.168.253.143/api/dcim/device-roles/" \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name": "Server",
  "slug": "server"
}'
```

## Verification

Navigate to:

```text
NetBox → DCIM → Device Roles
```

Confirm:

```text
Server
```

exists.

---

# Step 3 – Create Manufacturer

## Purpose

Creates a generic manufacturer entry used by virtual or custom-built servers.

### Manufacturer Details

| Property | Value   |
| -------- | ------- |
| Name     | Generic |
| Slug     | generic |

## Command

```bash
curl -X POST \
-k \
"https://192.168.253.143/api/dcim/manufacturers/" \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name": "Generic",
  "slug": "generic"
}'
```

## Verification

Navigate to:

```text
NetBox → DCIM → Manufacturers
```

Verify:

```text
Generic
```

exists.

---

# Step 4 – Create Device Type

## Purpose

Creates a generic x86 server model.

### Device Type Details

| Property        | Value              |
| --------------- | ------------------ |
| Manufacturer ID | 1                  |
| Model           | Generic x86 Server |
| Slug            | generic-x86-server |

## Command

```bash
curl -X POST \
-k \
"https://192.168.253.143/api/dcim/device-types/" \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "manufacturer": 1,
  "model": "Generic x86 Server",
  "slug": "generic-x86-server"
}'
```

## Verification

Navigate to:

```text
NetBox → DCIM → Device Types
```

Confirm:

```text
Generic x86 Server
```

exists.

---

# Step 5 – Create Site

## Purpose

Creates the primary NetBox site used by automation workflows.

### Site Details

| Property | Value  |
| -------- | ------ |
| Name     | VGS    |
| Slug     | vgs    |
| Status   | active |

## Command

```bash
#!/bin/bash

NETBOX_URL="https://192.168.253.143/api"
TOKEN="83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"

SITE_NAME="VGS"
SITE_SLUG="vgs"
SITE_STATUS="active"

curl -X POST -k "$NETBOX_URL/dcim/sites/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$SITE_NAME"'",
    "slug": "'"$SITE_SLUG"'",
    "status": "'"$SITE_STATUS"'"
  }'
```

### Alternative One-Liner

```bash
curl -X POST \
-k \
"https://192.168.253.143/api/dcim/sites/" \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name": "VGS",
  "slug": "vgs",
  "status": "active"
}'
```

## Verification

Navigate to:

```text
NetBox → DCIM → Sites
```

Confirm:

```text
VGS
```

exists and is active.

---

# Validation Checklist

## Connectivity

* [ ] NetBox API reachable
* [ ] API Token valid

## Objects Created

* [ ] Site (VGS)
* [ ] Device Role (Server)
* [ ] Manufacturer (Generic)
* [ ] Device Type (Generic x86 Server)
* [ ] Tag (new-build-rockyos)

## Final Validation

* [ ] API responses return HTTP 200/201
* [ ] Objects visible in NetBox UI
* [ ] Ready for AWX integration

---

# Completion Criteria

The environment is ready for AWX and provisioning automation when:

* Site exists.
* Device Role exists.
* Manufacturer exists.
* Device Type exists.
* Tag exists.
* API authentication succeeds.
* NetBox inventory objects can be created through automation.
