# Active Directory Domain Controller Build and Integration Guide

**Environment:** VGS Infrastructure Lab\
**Date:** 2026-08-24\
**Windows Server:** Windows Server 2022 Standard Evaluation (Desktop
Experience)\
**Domain Controller:** DC01\
**Active Directory Domain:** `vgs.com`\
**NetBIOS Name:** `VGS`\
**DC IP Address:** `192.168.253.161`\
**Technitium DNS:** `192.168.253.1`\
**Linux Example Host:** NetBox (`192.168.253.143`)

------------------------------------------------------------------------

# 1. Purpose

This document records the complete setup performed to build a Windows
Server 2022 Active Directory Domain Controller from scratch and
integrate it with the existing infrastructure.

The environment already uses **Technitium DNS** as the primary
infrastructure DNS server. Active Directory was configured with the
domain name:

``` text
vgs.com
```

The final architecture includes:

-   Windows Server 2022 Domain Controller
-   Active Directory Domain Services
-   Active Directory DNS
-   Windows Time / NTP
-   Technitium DNS integration
-   Linux DNS discovery
-   Rocky Linux / NetBox NTP synchronization
-   Preparation for Linux AD authentication
-   Preparation for VMware and vCenter integration
-   Active Directory user management

------------------------------------------------------------------------

# 2. Final Architecture

``` text
                         Internet NTP
                              |
                              v
                    +-------------------+
                    | External NTP      |
                    | Cloudflare / NPL  |
                    +-------------------+
                              |
                              v
                    +-------------------+
                    | DC01              |
                    | 192.168.253.161   |
                    | Windows Server    |
                    | AD DS             |
                    | DNS               |
                    | NTP               |
                    +-------------------+
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
 +----------------+   +----------------+   +----------------+
 | NetBox         |   | Linux Servers  |   | VMware         |
 | 192.168.253.143|   | Rocky/CentOS   |   | ESXi/vCenter   |
 +----------------+   +----------------+   +----------------+

                    Technitium DNS
                    192.168.253.1
```

------------------------------------------------------------------------

# 3. Windows Server Installation

Install:

``` text
Windows Server 2022 Standard Evaluation
Desktop Experience
```

## Recommended Server Edition

For most infrastructure servers requiring GUI management:

``` text
Windows Server 2022 Standard Evaluation (Desktop Experience)
```

This provides:

-   Start Menu
-   Desktop
-   File Explorer
-   Server Manager
-   MMC consoles
-   Active Directory graphical tools

For GUI-based Active Directory administration, Desktop Experience is
recommended for lab and small infrastructure environments.

------------------------------------------------------------------------

# 4. Initial Server Configuration

After Windows Server installation:

1.  Log in as `Administrator`.
2.  Open PowerShell as Administrator.
3.  Verify hostname.

``` powershell
hostname
```

Expected:

``` text
DC01
```

Check network configuration:

``` powershell
Get-NetIPConfiguration
```

Final DC01 network:

``` text
Hostname:        DC01
IP Address:      192.168.253.161
Default Gateway: 192.168.253.2
```

------------------------------------------------------------------------

# 5. Configure Static IP Address

Before installing Active Directory and DNS, the server must use a static
IP address.

Example commands:

``` powershell
Set-NetIPInterface -InterfaceAlias "Ethernet0" -Dhcp Disabled

New-NetIPAddress `
-InterfaceAlias "Ethernet0" `
-IPAddress 192.168.253.161 `
-PrefixLength 24 `
-DefaultGateway 192.168.253.2
```

Configure DNS temporarily as required during domain promotion.

After promotion, DC01 uses local DNS services:

``` text
127.0.0.1
::1
```

Verify:

``` powershell
Get-NetIPConfiguration
```

------------------------------------------------------------------------

# 6. Enable Remote Desktop

Enable RDP using PowerShell:

``` powershell
Set-ItemProperty `
-Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
-Name "fDenyTSConnections" `
-Value 0
```

Meaning:

``` text
fDenyTSConnections
```

Controls whether Terminal Services / Remote Desktop connections are
denied.

``` text
0 = Allow RDP connections
1 = Deny RDP connections
```

Enable the firewall rule:

``` powershell
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

------------------------------------------------------------------------

# 7. Enable SSH

Windows OpenSSH Server can be installed and configured to allow SSH
access.

Verify SSH access from an administrative workstation:

``` bash
ssh administrator@192.168.253.161
```

After domain promotion, login format can be:

``` text
VGS\Administrator
```

or:

``` text
administrator@vgs.com
```

------------------------------------------------------------------------

# 8. Install Active Directory and DNS Roles

Install the required Windows Server roles:

``` powershell
Install-WindowsFeature AD-Domain-Services,DNS -IncludeManagementTools
```

Verify:

``` powershell
Get-WindowsFeature AD-Domain-Services,DNS
```

Expected:

``` text
[X] Active Directory Domain Services
[X] DNS Server
```

------------------------------------------------------------------------

# 9. Initial Domain Issue and Rebuild

The first domain was accidentally created as:

``` text
vgs.local
```

The intended infrastructure domain is:

``` text
vgs.com
```

Therefore, the original domain controller configuration was removed and
Active Directory was rebuilt.

Important lesson:

> Confirm the final Active Directory domain name before promoting the
> first domain controller.

Final domain:

``` text
vgs.com
```

------------------------------------------------------------------------

# 10. Promote DC01 to Domain Controller

The domain controller was promoted as a new forest:

``` powershell
Install-ADDSForest `
-DomainName "vgs.com" `
-InstallDNS `
-CreateDnsDelegation:$false `
-DatabasePath "C:\Windows\NTDS" `
-SysvolPath "C:\Windows\SYSVOL" `
-LogPath "C:\Windows\NTDS" `
-Force
```

During promotion, configure the Directory Services Restore Mode (DSRM)
password.

After promotion, verify the domain.

``` powershell
Get-ADDomain
```

Final important values:

``` text
Domain:       vgs.com
NetBIOSName:  VGS
DNSRoot:      vgs.com
Forest:       vgs.com
PDC Emulator: DC01.vgs.com
```

------------------------------------------------------------------------

# 11. Verify Active Directory Forest

Run:

``` powershell
Get-ADForest
```

Expected:

``` text
Name:                  vgs.com
RootDomain:            vgs.com
Domains:               vgs.com
DomainNamingMaster:    DC01.vgs.com
SchemaMaster:          DC01.vgs.com
GlobalCatalogs:        DC01.vgs.com
```

------------------------------------------------------------------------

# 12. Verify Domain Controller

Run:

``` powershell
Get-ADDomainController
```

Important values:

``` text
Name:            DC01
Domain:          vgs.com
Forest:          vgs.com
HostName:        DC01.vgs.com
IPv4Address:    192.168.253.161
IsGlobalCatalog: True
LDAP Port:       389
SSL Port:        636
```

------------------------------------------------------------------------

# 13. Verify Active Directory DNS Zones

Run:

``` powershell
Get-DnsServerZone
```

Important zones:

``` text
vgs.com
_msdcs.vgs.com
```

The `vgs.com` zone contains Active Directory service records.

The `_msdcs.vgs.com` zone contains Microsoft-specific Active Directory
locator records.

------------------------------------------------------------------------

# 14. Verify DNS Records

Display records in the domain zone:

``` powershell
Get-DnsServerResourceRecord -ZoneName "vgs.com" |
Format-Table HostName,RecordType,RecordData -AutoSize
```

Important records include:

``` text
dc01                     A
_ldap._tcp               SRV
_kerberos._tcp           SRV
_gc._tcp                 SRV
_kpasswd._tcp            SRV
```

Check `_msdcs` records:

``` powershell
Get-DnsServerResourceRecord -ZoneName "_msdcs.vgs.com" |
Format-Table HostName,RecordType,RecordData -AutoSize
```

------------------------------------------------------------------------

# 15. Technitium DNS Integration

Existing infrastructure DNS:

``` text
Technitium DNS
IP: 192.168.253.1
Management Port: 5380
```

The Active Directory server is:

``` text
DC01.vgs.com
192.168.253.161
```

Because Technitium remains the primary DNS infrastructure, required AD
discovery records were created there.

## Set API Environment Variables

From the management workstation:

``` bash
export DNS_SERVER="192.168.253.1:5380"
export TOKEN="<TECHNITIUM_API_TOKEN>"
```

> Keep API tokens private. Do not commit them to Git repositories or
> documentation.

------------------------------------------------------------------------

# 16. Create DC01 A Record

``` bash
curl -G "http://${DNS_SERVER}/api/zones/records/add" \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "domain=dc01.vgs.com" \
  --data-urlencode "type=A" \
  --data-urlencode "ipAddress=192.168.253.161" \
  --data-urlencode "ttl=3600"
```

Verify:

``` bash
nslookup dc01.vgs.com 192.168.253.1
```

Expected:

``` text
dc01.vgs.com
192.168.253.161
```

------------------------------------------------------------------------

# 17. Create Active Directory SRV Records

## LDAP

``` bash
curl -G "http://${DNS_SERVER}/api/zones/records/add" \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "domain=_ldap._tcp.vgs.com" \
  --data-urlencode "type=SRV" \
  --data-urlencode "priority=0" \
  --data-urlencode "weight=100" \
  --data-urlencode "port=389" \
  --data-urlencode "target=dc01.vgs.com" \
  --data-urlencode "ttl=3600"
```

## Kerberos

``` bash
curl -G "http://${DNS_SERVER}/api/zones/records/add" \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "domain=_kerberos._tcp.vgs.com" \
  --data-urlencode "type=SRV" \
  --data-urlencode "priority=0" \
  --data-urlencode "weight=100" \
  --data-urlencode "port=88" \
  --data-urlencode "target=dc01.vgs.com" \
  --data-urlencode "ttl=3600"
```

## Global Catalog

``` bash
curl -G "http://${DNS_SERVER}/api/zones/records/add" \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "domain=_gc._tcp.vgs.com" \
  --data-urlencode "type=SRV" \
  --data-urlencode "priority=0" \
  --data-urlencode "weight=100" \
  --data-urlencode "port=3268" \
  --data-urlencode "target=dc01.vgs.com" \
  --data-urlencode "ttl=3600"
```

## Password Change TCP

``` bash
curl -G "http://${DNS_SERVER}/api/zones/records/add" \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "domain=_kpasswd._tcp.vgs.com" \
  --data-urlencode "type=SRV" \
  --data-urlencode "priority=0" \
  --data-urlencode "weight=100" \
  --data-urlencode "port=464" \
  --data-urlencode "target=dc01.vgs.com" \
  --data-urlencode "ttl=3600"
```

## Password Change UDP

``` bash
curl -G "http://${DNS_SERVER}/api/zones/records/add" \
  --data-urlencode "token=${TOKEN}" \
  --data-urlencode "domain=_kpasswd._udp.vgs.com" \
  --data-urlencode "type=SRV" \
  --data-urlencode "priority=0" \
  --data-urlencode "weight=100" \
  --data-urlencode "port=464" \
  --data-urlencode "target=dc01.vgs.com" \
  --data-urlencode "ttl=3600"
```

------------------------------------------------------------------------

# 18. Site-Specific SRV Records

Default AD site:

``` text
Default-First-Site-Name
```

LDAP:

``` text
_ldap._tcp.Default-First-Site-Name._sites.vgs.com
```

Kerberos:

``` text
_kerberos._tcp.Default-First-Site-Name._sites.vgs.com
```

Global Catalog:

``` text
_gc._tcp.Default-First-Site-Name._sites.vgs.com
```

These records point to:

``` text
dc01.vgs.com
```

------------------------------------------------------------------------

# 19. Forward `_msdcs.vgs.com` to DC01

A Technitium forwarder zone was created:

``` text
_msdcs.vgs.com
```

Forwarder:

``` text
192.168.253.161
```

This allows AD-specific Microsoft DNS records to remain managed by the
Active Directory DNS server while Technitium continues serving the main
infrastructure DNS.

------------------------------------------------------------------------

# 20. Verify DNS from Linux

Before joining Linux systems to Active Directory, verify that DNS resolution and Active Directory service discovery are working correctly.

On NetBox:

~~~bash
nslookup dc01.vgs.com
~~~

Expected result should resolve:

~~~text
DC01.vgs.com
192.168.253.161
~~~

## Verify LDAP SRV Record

~~~bash
nslookup -type=SRV _ldap._tcp.vgs.com
~~~

## Verify Kerberos SRV Record

~~~bash
nslookup -type=SRV _kerberos._tcp.vgs.com
~~~

## Verify Global Catalog

~~~bash
nslookup -type=SRV _gc._tcp.vgs.com
~~~

## Verify AD Locator Records

~~~bash
nslookup -type=SRV _ldap._tcp.dc._msdcs.vgs.com
~~~

These records are required for Linux systems to discover the Active Directory Domain Controller automatically.

---

# 21. Linux DNS Configuration

NetBox DNS configuration uses Technitium DNS.

Current configuration:

~~~text
search vgs.com
nameserver 192.168.253.1
~~~

The Linux servers continue using:

~~~text
Technitium DNS
192.168.253.1
~~~

Do not unnecessarily change all Linux servers to use the Domain Controller as their primary DNS server.

The infrastructure DNS architecture is:

~~~text
Linux Server
     |
     v
Technitium DNS
192.168.253.1
     |
     +--> Normal Infrastructure DNS
     |
     +--> Active Directory DNS Records
     |
     +--> _msdcs Forwarding
     |
     v
DC01
192.168.253.161
~~~

Technitium DNS provides normal infrastructure DNS resolution while forwarding Active Directory-specific requests to DC01.

---

# 22. Discover Active Directory from Linux

Verify that Rocky Linux can discover the Active Directory domain.

Run:

~~~bash
realm discover vgs.com
~~~

Expected result:

~~~text
vgs.com
  type: kerberos
  realm-name: VGS.COM
  domain-name: vgs.com
  configured: no
  server-software: active-directory
  client-software: sssd
~~~

Required packages may include:

~~~text
oddjob
oddjob-mkhomedir
sssd
adcli
samba-common-tools
~~~

Successful discovery confirms that:

- DNS is working
- LDAP SRV records are working
- Kerberos SRV records are working
- Active Directory discovery is working

---

# 23. Linux Active Directory Integration Preparation

Install the required packages on Rocky Linux.

~~~bash
dnf install -y \
realmd \
sssd \
sssd-ad \
adcli \
oddjob \
oddjob-mkhomedir \
samba-common-tools \
krb5-workstation
~~~

Verify installed packages:

~~~bash
rpm -qa | grep -E 'realmd|sssd|adcli|oddjob|krb5'
~~~

Expected packages include:

~~~text
realmd
sssd
sssd-ad
adcli
oddjob
oddjob-mkhomedir
krb5-workstation
~~~

Verify domain discovery again:

~~~bash
realm discover vgs.com
~~~

---

# 24. Why Time Synchronization Is Important

Active Directory authentication uses Kerberos.

Kerberos authentication is sensitive to time differences between:

- Linux client
- Domain Controller
- Kerberos KDC

If the time difference is too large, authentication can fail.

The recommended infrastructure time hierarchy is:

~~~text
External NTP
     |
     v
DC01
     |
     +--> NetBox
     +--> Foreman
     +--> AWX
     +--> Linux Servers
~~~

Therefore, DC01 is configured as the internal NTP server.

---

# 25. Verify Windows Time Service on DC01

On DC01 PowerShell:

~~~powershell
Get-Service w32time
~~~

Expected:

~~~text
Status   Name      DisplayName
------   ----      -----------
Running  w32time   Windows Time
~~~

Verify that UDP port 123 is listening:

~~~powershell
Get-NetUDPEndpoint -LocalPort 123
~~~

Expected:

~~~text
LocalAddress    LocalPort
------------    ---------
::              123
0.0.0.0         123
~~~

Verify the process listening on UDP 123:

~~~powershell
netstat -ano -p udp | findstr ":123"
~~~

---

# 26. Verify Windows Firewall NTP Rules

Run:

~~~powershell
Get-NetFirewallRule | Where-Object {
    $_.DisplayName -match "NTP|Windows Time"
} | Format-Table DisplayName, Enabled, Direction, Action
~~~

Important rules:

~~~text
Active Directory Domain Controller - W32Time (NTP-UDP-In)

Windows Time NTP Server
~~~

Both should show:

~~~text
Enabled: True
Direction: Inbound
Action: Allow
~~~

Verify the firewall port configuration:

~~~powershell
Get-NetFirewallRule -DisplayName "Active Directory Domain Controller - W32Time (NTP-UDP-In)" |
Get-NetFirewallPortFilter
~~~

Verify the second rule:

~~~powershell
Get-NetFirewallRule -DisplayName "Windows Time NTP Server" |
Get-NetFirewallPortFilter
~~~

Expected:

~~~text
Protocol  : UDP
LocalPort : 123
~~~

---

# 27. Verify DC01 Network Profile

Run:

~~~powershell
Get-NetConnectionProfile
~~~

Example:

~~~text
Name             : Network
InterfaceAlias   : Ethernet0
NetworkCategory  : Private
IPv4Connectivity : LocalNetwork
~~~

Ensure that firewall rules are applicable to the active network profile.

---

# 28. Configure DC01 Upstream NTP

DC01 should synchronize from reliable external NTP sources.

Current configured sources:

~~~text
www.time.nplindia.org
time.cloudflare.com
~~~

Check the Windows Time configuration:

~~~powershell
w32tm /query /configuration
~~~

Verify status:

~~~powershell
w32tm /query /status
~~~

Verify source:

~~~powershell
w32tm /query /source
~~~

Successful example:

~~~text
Source: time.cloudflare.com
~~~

Example status:

~~~text
Leap Indicator: 0(no warning)
Stratum: 4
Source: time.cloudflare.com
~~~

This confirms:

~~~text
External NTP
     |
     v
DC01
~~~

---

# 29. Verify Windows NTP Server Provider

Verify the Windows NTP server provider:

~~~powershell
Get-ItemProperty `
-Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer"
~~~

Important value:

~~~text
Enabled : 1
~~~

This confirms that the Windows Time NTP Server provider is enabled.

---

# 30. Disable VMware Time Provider on DC01

Because DC01 is running as a VMware virtual machine, the VMware Integration Time Provider can interfere with the desired Active Directory time hierarchy.

Disable the VMware Integration Time Provider:

~~~powershell
Set-ItemProperty `
-Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider" `
-Name "Enabled" `
-Value 0
~~~

Restart Windows Time:

~~~powershell
Restart-Service w32time
~~~

Verify:

~~~powershell
w32tm /query /configuration
~~~

Expected:

~~~text
VMICTimeProvider
Enabled: 0
~~~

---

# 31. Configure DC01 as a Reliable NTP Server

Configure DC01 as a reliable internal time source:

~~~powershell
w32tm /config /reliable:yes /update
~~~

Restart the Windows Time service:

~~~powershell
Restart-Service w32time
~~~

Verify:

~~~powershell
w32tm /query /configuration
~~~

The Domain Controller is now configured as the internal infrastructure NTP server.

---

# 32. Verify DC01 NTP Service Locally

Test NTP locally:

~~~powershell
w32tm /stripchart /computer:127.0.0.1 /samples:5 /dataonly
~~~

Expected successful samples:

~~~text
+00.0001176s
+00.0000921s
+00.0001103s
~~~

This confirms that the local Windows NTP server is responding.

---

# 33. Verify DC01 NTP Service Through Network IP

Test the NTP server using the DC01 IP address:

~~~powershell
w32tm /stripchart /computer:192.168.253.161 /samples:5 /dataonly
~~~

Expected successful samples:

~~~text
+00.0001630s
+00.0001046s
+00.0001269s
~~~

This confirms:

~~~text
DC01
192.168.253.161
UDP 123
NTP Server
Working
~~~

---

# 34. Test NTP UDP Port from NetBox

On NetBox:

~~~bash
nmap -sU -p 123 192.168.253.161
~~~

Successful result:

~~~text
PORT    STATE SERVICE
123/udp open  ntp
~~~

This confirms that UDP port 123 is reachable from NetBox.

---

# 35. Capture NTP Traffic from NetBox

Capture NTP packets:

~~~bash
tcpdump -ni any udp port 123 and host 192.168.253.161
~~~

Successful traffic showed:

~~~text
192.168.253.143 > 192.168.253.161.ntp: NTPv4, Client

192.168.253.161.ntp > 192.168.253.143: NTPv3, Server
~~~

This confirms bidirectional communication:

~~~text
NetBox
   |
   | NTP Request
   v
DC01
   |
   | NTP Response
   v
NetBox
~~~

Therefore:

~~~text
Network Connectivity: Working
UDP Port 123: Working
DC01 NTP Response: Working
~~~

---

# 36. Configure NetBox to Use DC01 NTP

Back up the existing Chrony configuration:

~~~bash
cp -a /etc/chrony.conf /etc/chrony.conf.backup
~~~

Edit the Chrony configuration:

~~~bash
vi /etc/chrony.conf
~~~

Configure DC01 as the preferred NTP server:

~~~text
server 192.168.253.161 iburst prefer
~~~

Restart Chrony:

~~~bash
systemctl restart chronyd
~~~

Verify the NTP sources:

~~~bash
chronyc sources -v
~~~

Successful result:

~~~text
^* 192.168.253.161
~~~

Meaning:

~~~text
^ = NTP Server
* = Current Selected Time Source
~~~

This confirms:

~~~text
NetBox
   |
   v
DC01
   |
   v
External NTP
~~~

---

# 37. Verify Chrony Tracking

Run:

~~~bash
chronyc tracking
~~~

The reference ID should correspond to:

~~~text
192.168.253.161
~~~

Also verify:

~~~bash
timedatectl
~~~

The Linux system should now synchronize through DC01.

---

# 38. Active Directory GUI Management

Open Active Directory Users and Computers.

Press:

~~~text
Windows + R
~~~

Run:

~~~text
dsa.msc
~~~

Navigate:

~~~text
Active Directory Users and Computers
|
+-- vgs.com
    |
    +-- Users
    +-- Computers
    +-- Domain Controllers
    +-- Builtin
~~~

---

# 39. Organizational Unit Design

The recommended Active Directory structure is:

~~~text
vgs.com
|
├── Users-VGS
│
├── Groups-VGS
│
├── Servers-VGS
│   |
│   ├── Linux-Servers
│   |
│   └── Windows-Servers
│
├── Service-Accounts-VGS
│
└── Workstations-VGS
~~~

This structure separates:

- Users
- Security Groups
- Servers
- Service Accounts
- Workstations

---

# 40. Create Organizational Units

Create the following Organizational Units under `vgs.com`.

~~~text
Users-VGS
Groups-VGS
Servers-VGS
Service-Accounts-VGS
Workstations-VGS
~~~

## Create Users-VGS

In Active Directory Users and Computers:

~~~text
vgs.com
  |
  +-- Right Click
       |
       +-- New
            |
            +-- Organizational Unit
~~~

Name:

~~~text
Users-VGS
~~~

Keep the following option enabled:

~~~text
Protect container from accidental deletion
~~~

Click:

~~~text
OK
~~~

---

# 41. Create Groups-VGS

Create:

~~~text
Groups-VGS
~~~

Recommended location:

~~~text
vgs.com
|
+-- Groups-VGS
~~~

Keep accidental deletion protection enabled.

---

# 42. Create Servers-VGS

Create:

~~~text
Servers-VGS
~~~

The structure becomes:

~~~text
vgs.com
|
+-- Servers-VGS
~~~

---

# 43. Create Linux-Servers OU

Inside:

~~~text
Servers-VGS
~~~

Create:

~~~text
Linux-Servers
~~~

Final structure:

~~~text
Servers-VGS
|
+-- Linux-Servers
~~~

This OU is used for Linux computer accounts joined to Active Directory.

---

# 44. Create Windows-Servers OU

Inside:

~~~text
Servers-VGS
~~~

Create:

~~~text
Windows-Servers
~~~

Final structure:

~~~text
Servers-VGS
|
├── Linux-Servers
|
└── Windows-Servers
~~~

This provides separation between Linux and Windows computer accounts.

---

# 45. Create Service-Accounts-VGS

Create:

~~~text
Service-Accounts-VGS
~~~

This OU is reserved for service accounts used by infrastructure applications.

Examples:

~~~text
svc_awx
svc_netbox
svc_foreman
svc_vmware
~~~

Do not use normal administrator accounts for application service accounts.

---

# 46. Create Workstations-VGS

Create:

~~~text
Workstations-VGS
~~~

This OU will contain Active Directory joined user computers and workstations.

---

# 47. Final Organizational Unit Structure

The completed OU structure is:

~~~text
vgs.com
|
├── Users-VGS
│
├── Groups-VGS
│
├── Servers-VGS
│   |
│   ├── Linux-Servers
│   |
│   └── Windows-Servers
│
├── Service-Accounts-VGS
│
└── Workstations-VGS
~~~

---

# 48. Recommended Security Groups

Inside:

~~~text
Groups-VGS
~~~

Create the following security groups:

~~~text
Linux-Admins
VMware-Admins
Infrastructure-Admins
AD-Admins
~~~

Recommended group configuration:

~~~text
Group Scope: Global
Group Type: Security
~~~

---

# 49. Security Group Purpose

## Linux-Admins

Used to provide administrative access to Linux servers.

Future permission model:

~~~text
Linux-Admins
      |
      v
Linux Servers
      |
      v
sudo Access
~~~

## VMware-Admins

Used for VMware infrastructure administration.

Future permission model:

~~~text
VMware-Admins
      |
      +--> vCenter
      |
      +--> ESXi
~~~

## Infrastructure-Admins

Used for infrastructure-level administration.

Future systems may include:

~~~text
NetBox
Foreman
AWX
DNS
Infrastructure Management Tools
~~~

## AD-Admins

Reserved for Active Directory administration.

This group should be used carefully.

---

# 50. Create Active Directory User

The infrastructure user created is:

~~~text
Display Name: Vignesh S
Username: vignesh
UPN: vignesh@vgs.com
~~~

The user was moved to:

~~~text
OU=Users-VGS
DC=vgs
DC=com
~~~

Verify:

~~~powershell
Get-ADUser vignesh -Properties MemberOf |
Select-Object Name,SamAccountName,UserPrincipalName,MemberOf
~~~

Expected:

~~~text
Name: Vignesh S
SamAccountName: vignesh
UserPrincipalName: vignesh@vgs.com
~~~

---

# 51. Add User to Linux-Admins

Verify Linux-Admins group membership:

~~~powershell
Get-ADGroupMember "Linux-Admins"
~~~

Successful result:

~~~text
Name           : Vignesh S
SamAccountName : vignesh
~~~

The user is now a member of:

~~~text
Linux-Admins
~~~

---

# 52. Add User to Infrastructure-Admins

Verify Infrastructure-Admins membership:

~~~powershell
Get-ADGroupMember "Infrastructure-Admins"
~~~

Successful result:

~~~text
distinguishedName : CN=Vignesh S,OU=Users-VGS,DC=vgs,DC=com
name              : Vignesh S
SamAccountName    : vignesh
~~~

The user is now located correctly inside:

~~~text
OU=Users-VGS
DC=vgs
DC=com
~~~

---

# 53. Verify User Group Membership

Run:

~~~powershell
Get-ADUser vignesh -Properties MemberOf |
Select-Object Name,SamAccountName,UserPrincipalName,MemberOf
~~~

The user should be a member of:

~~~text
Linux-Admins
Infrastructure-Admins
~~~

Permission architecture:

~~~text
Vignesh S
    |
    +--> Linux-Admins
    |
    +--> Infrastructure-Admins
~~~

This follows the recommended model:

~~~text
User
  |
  v
Security Group
  |
  v
Permission
~~~

Do not assign infrastructure permissions directly to individual users when group-based access can be used.

---

# 54. Verify NetBox Hostname

On NetBox:

~~~bash
hostname -f
~~~

Successful result:

~~~text
netbox.vgs.com
~~~

This confirms the Linux hostname is configured for the Active Directory domain namespace.

---

# 55. Verify Active Directory Discovery Before Join

Run:

~~~bash
realm discover vgs.com
~~~

Successful result:

~~~text
vgs.com
  type: kerberos
  realm-name: VGS.COM
  domain-name: vgs.com
  configured: no
  server-software: active-directory
  client-software: sssd
~~~

Verify time synchronization:

~~~bash
chronyc sources -v
~~~

Successful result:

~~~text
^* 192.168.253.161
~~~

This confirms:

~~~text
DNS: Working
NTP: Working
AD Discovery: Working
~~~

---

# 56. Initial Active Directory Join Attempt

The initial join command was:

~~~bash
realm join vgs.com \
  --user=Administrator \
  --computer-ou="OU=Linux-Servers,OU=Servers-VGS,DC=vgs,DC=com"
~~~

Initial error:

~~~text
KDC has no support for encryption type
~~~

The Kerberos configuration was reviewed.

The previous configuration contained an incorrect realm:

~~~text
default_realm = VGS.LOCAL
~~~

The correct Active Directory domain is:

~~~text
vgs.com
~~~

The correct Kerberos realm is:

~~~text
VGS.COM
~~~

---

# 57. Correct Kerberos Configuration

Back up the existing configuration:

~~~bash
cp -a /etc/krb5.conf /etc/krb5.conf.backup.$(date +%F-%H%M%S)
~~~

Configure:

~~~bash
cat > /etc/krb5.conf <<'EOF'
includedir /etc/krb5.conf.d/

[logging]
    default = FILE:/var/log/krb5libs.log

[libdefaults]
    default_realm = VGS.COM
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    default_ccache_name = KEYRING:persistent:%{uid}
    udp_preference_limit = 0

[domain_realm]
    .vgs.com = VGS.COM
    vgs.com = VGS.COM
EOF
~~~

Verify:

~~~bash
cat /etc/krb5.conf
~~~

The important settings are:

~~~text
default_realm = VGS.COM

.vgs.com = VGS.COM
vgs.com = VGS.COM
~~~

---

# 58. Verify Linux Crypto Policy

Check the current crypto policy:

~~~bash
update-crypto-policies --show
~~~

Current result:

~~~text
DEFAULT
~~~

Check permitted encryption types:

~~~bash
grep -RniE \
'permitted_enctypes|default_tkt_enctypes|default_tgs_enctypes' \
/etc/krb5.conf /etc/krb5.conf.d 2>/dev/null
~~~

The system supports modern AES encryption types.

---

# 59. Verify Active Directory Encryption Configuration

On DC01:

~~~powershell
Get-ADComputer DC01 -Properties msDS-SupportedEncryptionTypes |
Select-Object Name,DNSHostName,msDS-SupportedEncryptionTypes
~~~

Successful result:

~~~text
Name  DNSHostName   msDS-SupportedEncryptionTypes
----  -----------   -----------------------------
DC01  DC01.vgs.com  28
~~~

The Domain Controller supports the required modern encryption types.

---

# 60. Test Kerberos Authentication

Clear any existing Kerberos credentials:

~~~bash
kdestroy
~~~

Authenticate against Active Directory:

~~~bash
kinit Administrator@VGS.COM
~~~

Enter the Active Directory Administrator password.

Verify the Kerberos ticket:

~~~bash
klist
~~~

Successful result:

~~~text
Ticket cache: KCM:0

Default principal:
Administrator@VGS.COM

Service principal:
krbtgt/VGS.COM@VGS.COM
~~~

This confirms:

~~~text
Linux
   |
   v
Kerberos
   |
   v
Active Directory
VGS.COM
   |
   v
Authentication Working
~~~

---

# 61. Remove Previous Incorrect Domain Membership

NetBox was previously joined to an incorrect domain:

~~~text
vgs.local
~~~

Verify:

~~~bash
realm list
~~~

Previous result:

~~~text
vgs.local
  realm-name: VGS.LOCAL
  domain-name: vgs.local
~~~

This was incorrect because the actual Active Directory domain is:

~~~text
vgs.com
~~~

Remove the old realm:

~~~bash
realm leave vgs.local
~~~

Verify:

~~~bash
realm list
~~~

Expected result after removal:

~~~text
No configured realm
~~~

---

# 62. Join NetBox to vgs.com

Join NetBox to Active Directory:

~~~bash
realm join vgs.com \
  --user=Administrator \
  --computer-ou="OU=Linux-Servers,OU=Servers-VGS,DC=vgs,DC=com"
~~~

Enter the Active Directory Administrator password when prompted.

The join completed successfully.

---

# 63. Verify NetBox Active Directory Membership

Run:

~~~bash
realm list
~~~

Successful result:

~~~text
vgs.com
  type: kerberos
  realm-name: VGS.COM
  domain-name: vgs.com
  configured: kerberos-member
  server-software: active-directory
  client-software: sssd
  required-package: oddjob
  required-package: oddjob-mkhomedir
  required-package: sssd
  required-package: adcli
  required-package: samba-common-tools
  login-formats: %U@vgs.com
  login-policy: allow-realm-logins
~~~

This confirms that NetBox is now successfully joined to:

~~~text
vgs.com
~~~

---

# 64. Verify Active Directory User Lookup from NetBox

Test the Active Directory user:

~~~bash
id vignesh@vgs.com
~~~

Successful result:

~~~text
uid=873601107(vignesh@vgs.com)
gid=873600513(domain users@vgs.com)

groups=
domain users@vgs.com
infrastructure-admins@vgs.com
linux-admins@vgs.com
~~~

This confirms:

~~~text
Active Directory User Lookup: Working
SSSD: Working
Kerberos: Working
Group Membership Resolution: Working
Linux-Admins Group: Detected
Infrastructure-Admins Group: Detected
~~~

---

# 65. Current NetBox Active Directory Integration Status

Current status:

| Component | Status |
|---|---|
| NetBox Hostname | Working |
| `netbox.vgs.com` | Working |
| DNS Resolution | Working |
| Technitium DNS | Working |
| AD SRV Discovery | Working |
| Kerberos Discovery | Working |
| DC01 NTP | Working |
| NetBox Time Sync | Working |
| Kerberos Authentication | Working |
| `kinit Administrator@VGS.COM` | Working |
| Active Directory Join | Working |
| `realm list` | Working |
| SSSD User Lookup | Working |
| AD Group Lookup | Working |
| `vignesh@vgs.com` | Working |
| Linux-Admins Group | Working |
| Infrastructure-Admins Group | Working |

---

# 66. Final Active Directory Structure

The current Active Directory structure is:

~~~text
vgs.com
|
├── Users-VGS
│   |
│   └── Vignesh S
│       |
│       └── vignesh@vgs.com
│
├── Groups-VGS
│   |
│   ├── Linux-Admins
│   │       |
│   │       └── Vignesh S
│   |
│   ├── Infrastructure-Admins
│   │       |
│   │       └── Vignesh S
│   |
│   ├── VMware-Admins
│   |
│   └── AD-Admins
│
├── Servers-VGS
│   |
│   ├── Linux-Servers
│   │       |
│   │       └── NetBox
│   |
│   └── Windows-Servers
│
├── Service-Accounts-VGS
│
└── Workstations-VGS
~~~

---

# 67. Current Authentication Architecture

The authentication architecture is now:

~~~text
                     External NTP
                         |
                         v
                 www.time.nplindia.org
                 time.cloudflare.com
                         |
                         v
                  DC01.vgs.com
               192.168.253.161
                         |
              +----------+----------+
              |                     |
              v                     v
           Active Directory       NTP Server
              |
              v
         vgs.com Domain
              |
              v
       Technitium DNS
       192.168.253.1
              |
              v
        Linux Infrastructure
              |
       +------+------+------+
       |             |      |
       v             v      v
     NetBox        Foreman  AWX
       |
       v
     SSSD
       |
       v
 Active Directory Users
       |
       v
 vignesh@vgs.com
       |
       +--> Linux-Admins
       |
       +--> Infrastructure-Admins
~~~

---

# 68. Important Operational Notes

## DNS

Infrastructure DNS remains:

~~~text
Technitium DNS
192.168.253.1
~~~

Active Directory Domain Controller:

~~~text
DC01.vgs.com
192.168.253.161
~~~

Linux systems should continue using Technitium DNS unless a specific Active Directory requirement requires otherwise.

## Active Directory Domain

Use:

~~~text
Domain: vgs.com
Kerberos Realm: VGS.COM
~~~

Do not use:

~~~text
vgs.local
VGS.LOCAL
~~~

The previous incorrect realm membership was removed.

## Time Hierarchy

The correct hierarchy is:

~~~text
External NTP
     |
     v
DC01
192.168.253.161
     |
     +--> NetBox
     +--> Foreman
     +--> AWX
     +--> Linux Servers
~~~

---

# 69. Important Verification Commands

## Windows Active Directory

~~~powershell
Get-ADDomain
Get-ADForest
Get-ADDomainController
Get-DnsServerZone
Get-Service NTDS
Get-Service w32time
w32tm /query /status
w32tm /query /source
~~~

## Verify Active Directory User

~~~powershell
Get-ADUser vignesh -Properties MemberOf |
Select-Object Name,SamAccountName,UserPrincipalName,MemberOf
~~~

## Verify Linux-Admins

~~~powershell
Get-ADGroupMember "Linux-Admins"
~~~

## Verify Infrastructure-Admins

~~~powershell
Get-ADGroupMember "Infrastructure-Admins"
~~~

## Linux DNS

~~~bash
hostname -f
realm discover vgs.com
nslookup dc01.vgs.com
nslookup -type=SRV _ldap._tcp.vgs.com
nslookup -type=SRV _kerberos._tcp.vgs.com
nslookup -type=SRV _gc._tcp.vgs.com
nslookup -type=SRV _ldap._tcp.dc._msdcs.vgs.com
~~~

## Linux Time

~~~bash
timedatectl
chronyc sources -v
chronyc tracking
~~~

## Kerberos

~~~bash
kinit Administrator@VGS.COM
klist
kdestroy
~~~

## Active Directory Membership

~~~bash
realm list
~~~

## Active Directory User Lookup

~~~bash
id vignesh@vgs.com
~~~

## Verify SSSD

~~~bash
systemctl status sssd
~~~

---

# 70. Current Environment Status

| Component | Status |
|---|---|
| Windows Server 2022 | Working |
| DC01 | Working |
| Active Directory | Working |
| Domain | `vgs.com` |
| Kerberos Realm | `VGS.COM` |
| Domain Controller | `DC01.vgs.com` |
| DC IP | `192.168.253.161` |
| Technitium DNS | Working |
| Technitium DNS IP | `192.168.253.1` |
| AD DNS Discovery | Working |
| LDAP SRV Records | Working |
| Kerberos SRV Records | Working |
| Global Catalog | Working |
| `_msdcs` Forwarding | Working |
| Windows Time Service | Working |
| DC01 NTP Server | Working |
| NetBox NTP | Working |
| NetBox AD Discovery | Working |
| OUs | Created |
| Security Groups | Created |
| AD User | Created |
| User Group Membership | Working |
| Kerberos Authentication | Working |
| NetBox AD Join | Working |
| NetBox SSSD | Working |
| AD User Lookup from NetBox | Working |
| Linux-Admins Lookup | Working |
| Infrastructure-Admins Lookup | Working |
| Linux AD Login | Next Step |
| Linux AD sudo Access | Next Step |
| Foreman AD Integration | Planned |
| AWX AD Integration | Planned |
| vCenter AD Integration | Planned |
| ESXi AD Integration | Planned |

---

# 71. Final Status

The following infrastructure components have now been successfully implemented:

~~~text
Active Directory Domain
        |
        v
vgs.com
        |
        v
Domain Controller
        |
        v
DC01.vgs.com
192.168.253.161
        |
        +--> Active Directory
        |
        +--> DNS
        |
        +--> Kerberos
        |
        +--> LDAP
        |
        +--> Global Catalog
        |
        +--> NTP Server
                 |
                 v
            NetBox Server
            netbox.vgs.com
                 |
                 v
              SSSD
                 |
                 v
       Active Directory Users
                 |
                 v
          vignesh@vgs.com
                 |
        +--------+--------+
        |                 |
        v                 v
 Linux-Admins   Infrastructure-Admins
~~~

The NetBox server is successfully joined to:

~~~text
vgs.com
~~~

Active Directory user lookup is successfully working:

~~~bash
id vignesh@vgs.com
~~~

The next implementation phase is:

~~~text
Active Directory Integration
        |
        v
Configure SSSD Login
        |
        v
Test AD User SSH Login
        |
        v
Configure Automatic Home Directory
        |
        v
Configure sudo Access
        |
        v
Linux-Admins -> sudo
        |
        v
Integrate Additional Linux Servers
        |
        +--> Foreman
        |
        +--> AWX
        |
        +--> Other Linux Servers
        |
        v
vCenter Active Directory Integration
        |
        v
ESXi Active Directory Integration
~~~

# End of Document
