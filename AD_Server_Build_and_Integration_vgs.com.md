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

On NetBox:

``` bash
nslookup dc01.vgs.com
```

Verify LDAP:

``` bash
nslookup -type=SRV _ldap._tcp.vgs.com
```

Verify Kerberos:

``` bash
nslookup -type=SRV _kerberos._tcp.vgs.com
```

Verify Global Catalog:

``` bash
nslookup -type=SRV _gc._tcp.vgs.com
```

Verify AD locator records:

``` bash
nslookup -type=SRV _ldap._tcp.dc._msdcs.vgs.com
```

------------------------------------------------------------------------

# 21. Linux DNS Configuration

NetBox DNS configuration:

``` text
search vgs.com
nameserver 192.168.253.1
```

The Linux servers continue using Technitium DNS:

``` text
192.168.253.1
```

Technitium provides normal infrastructure DNS and the required Active
Directory discovery records.

------------------------------------------------------------------------

# 22. Discover Active Directory from Linux

On Rocky Linux:

``` bash
realm discover vgs.com
```

Expected:

``` text
type: kerberos
realm-name: VGS.COM
domain-name: vgs.com
server-software: active-directory
client-software: sssd
```

Required packages may include:

``` text
oddjob
oddjob-mkhomedir
sssd
adcli
samba-common-tools
```

------------------------------------------------------------------------

# 23. Linux AD Integration Preparation

Install packages:

``` bash
dnf install -y realmd sssd adcli oddjob oddjob-mkhomedir samba-common-tools krb5-workstation
```

Discover:

``` bash
realm discover vgs.com
```

Join:

``` bash
realm join vgs.com -U Administrator
```

Verify:

``` bash
realm list
```

Expected login format:

``` text
user@vgs.com
```

Example:

``` bash
id vicky@vgs.com
```

------------------------------------------------------------------------

# 24. Why Time Synchronization Is Important

Active Directory authentication uses Kerberos.

Kerberos is sensitive to time differences.

If the Linux server and Domain Controller have significantly different
time, authentication can fail.

Therefore, internal infrastructure should synchronize to a consistent
time source.

------------------------------------------------------------------------

# 25. Configure DC01 as NTP Server

Windows Time service:

``` powershell
Get-Service w32time
```

Expected:

``` text
Running
```

Verify UDP port 123:

``` powershell
Get-NetUDPEndpoint -LocalPort 123
```

Expected:

``` text
0.0.0.0:123
:: :123
```

Verify firewall:

``` powershell
Get-NetFirewallRule | Where-Object {
    $_.DisplayName -match "NTP|Windows Time"
} | Format-Table DisplayName, Enabled, Direction, Action
```

Important rules:

``` text
Active Directory Domain Controller - W32Time (NTP-UDP-In)
Windows Time NTP Server
```

Both should be:

``` text
Enabled: True
Direction: Inbound
Action: Allow
```

------------------------------------------------------------------------

# 26. Configure DC01 Upstream NTP

The Domain Controller synchronizes from external NTP sources.

Example configuration:

``` text
www.time.nplindia.org
time.cloudflare.com
```

Check configuration:

``` powershell
w32tm /query /configuration
```

Check status:

``` powershell
w32tm /query /status
```

Check source:

``` powershell
w32tm /query /source
```

Example:

``` text
Source: time.cloudflare.com
```

------------------------------------------------------------------------

# 27. Disable VMware Time Provider on DC01

Because DC01 is a VMware virtual machine, the VMware Integration Time
Provider can interfere with domain time hierarchy.

Disable it:

``` powershell
Set-ItemProperty `
-Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider" `
-Name "Enabled" `
-Value 0
```

Restart:

``` powershell
Restart-Service w32time
```

Configure DC01 as a reliable time server:

``` powershell
w32tm /config /reliable:yes /update
Restart-Service w32time
```

------------------------------------------------------------------------

# 28. Verify DC01 NTP Service

Test locally:

``` powershell
w32tm /stripchart /computer:127.0.0.1 /samples:5 /dataonly
```

Test via DC IP:

``` powershell
w32tm /stripchart /computer:192.168.253.161 /samples:5 /dataonly
```

Successful samples confirm the NTP service is responding.

------------------------------------------------------------------------

# 29. Test NTP from NetBox

Test UDP port:

``` bash
nmap -sU -p 123 192.168.253.161
```

Successful result:

``` text
123/udp open ntp
```

Capture packets:

``` bash
tcpdump -ni any udp port 123 and host 192.168.253.161
```

Successful traffic showed:

``` text
NetBox -> DC01: NTPv4 Client
DC01 -> NetBox: NTPv3 Server
```

This confirmed bidirectional NTP communication.

------------------------------------------------------------------------

# 30. Configure NetBox to Use DC01 NTP

Back up Chrony configuration:

``` bash
cp -a /etc/chrony.conf /etc/chrony.conf.backup
```

Edit:

``` bash
vi /etc/chrony.conf
```

Add:

``` text
server 192.168.253.161 iburst prefer
```

Restart:

``` bash
systemctl restart chronyd
```

Verify:

``` bash
chronyc sources -v
```

Successful result:

``` text
^* 192.168.253.161
```

Meaning:

``` text
^ = NTP server
* = Selected synchronization source
```

This confirms:

``` text
NetBox -> DC01 -> External NTP
```

is working.

------------------------------------------------------------------------

# 31. Verify Chrony Tracking

Run:

``` bash
chronyc tracking
```

The reference ID should correspond to:

``` text
192.168.253.161
```

This confirms NetBox is synchronized through the Active Directory Domain
Controller.

------------------------------------------------------------------------

# 32. Active Directory GUI Management

Open Active Directory Users and Computers:

``` text
Windows + R
```

Run:

``` text
dsa.msc
```

Navigate:

``` text
Active Directory Users and Computers
|
+-- vgs.com
    |
    +-- Users
    +-- Computers
    +-- Domain Controllers
    +-- Builtin
```

------------------------------------------------------------------------

# 33. Create a User Using GUI

Navigate to:

``` text
vgs.com
|
+-- Users
```

Right-click:

``` text
Users
 -> New
 -> User
```

Example:

``` text
First name:       Vicky
Last name:        Admin
User logon name:  vicky
```

The UPN becomes:

``` text
vicky@vgs.com
```

The pre-Windows 2000 login format is:

``` text
VGS\vicky
```

Set a password and choose the appropriate password policy.

------------------------------------------------------------------------

# 34. Recommended Active Directory Structure

Recommended future structure:

``` text
vgs.com
|
+-- OU=Users
|
+-- OU=Groups
|   |
|   +-- Linux-Admins
|   +-- VMware-Admins
|   +-- Infrastructure-Admins
|
+-- OU=Servers
|   |
|   +-- Linux-Servers
|   +-- Windows-Servers
|
+-- OU=Service-Accounts
|
+-- OU=Workstations
```

Best practice:

> Assign permissions to security groups rather than directly assigning
> permissions to individual users.

------------------------------------------------------------------------

# 35. Recommended Security Groups

Create:

``` text
Linux-Admins
VMware-Admins
Infrastructure-Admins
AD-Admins
```

Future permission model:

``` text
User
  |
  v
Security Group
  |
  v
Permission
  |
  +--> Linux Servers
  +--> vCenter
  +--> ESXi
  +--> NetBox
  +--> Foreman
  +--> AWX
```

------------------------------------------------------------------------

# 36. Current Environment Status

  Component                   Status
  --------------------------- -------------------
  Windows Server 2022         Working
  DC01                        Working
  Active Directory            Working
  Domain                      `vgs.com`
  Domain Controller           `DC01.vgs.com`
  DC IP                       `192.168.253.161`
  Active Directory DNS        Working
  Technitium DNS              Working
  AD DNS Discovery            Working
  LDAP SRV Record             Working
  Kerberos SRV Record         Working
  Global Catalog SRV Record   Working
  `_msdcs` Forwarding         Working
  Windows Time Service        Working
  DC01 NTP Server             Working
  NetBox NTP                  Working
  NetBox AD Discovery         Working
  AD User Creation            Next Step
  Linux AD Login              Next Step
  ESXi AD Integration         Planned
  vCenter AD Integration      Planned

------------------------------------------------------------------------

# 37. Next Steps

The recommended next implementation order is:

1.  Create Organizational Units (OUs).
2.  Create security groups.
3.  Create Active Directory users.
4.  Join NetBox and other Linux servers to `vgs.com`.
5.  Configure Linux AD authentication using SSSD.
6.  Configure sudo access through AD groups.
7.  Integrate vCenter with Active Directory.
8.  Integrate ESXi authentication with Active Directory.
9.  Create service accounts where required.
10. Apply role-based access control (RBAC).

------------------------------------------------------------------------

# 38. Important Operational Notes

## DNS

The infrastructure currently uses:

``` text
Technitium DNS: 192.168.253.1
```

Do not unnecessarily change all Linux servers to use the Domain
Controller as their primary DNS server.

Instead:

``` text
Linux Server
     |
     v
Technitium DNS
192.168.253.1
     |
     +--> Normal infrastructure DNS
     |
     +--> Active Directory SRV records
     |
     +--> _msdcs forwarding
     |
     v
DC01
192.168.253.161
```

## Time

The recommended hierarchy is:

``` text
External NTP
     |
     v
DC01
     |
     +--> NetBox
     +--> Foreman
     +--> AWX
     +--> Linux Servers
```

## Active Directory

Use:

``` text
vgs.com
```

Avoid recreating the domain unless there is a major architectural
reason.

------------------------------------------------------------------------

# 39. Useful Verification Commands

## Windows / Active Directory

``` powershell
Get-ADDomain
Get-ADForest
Get-ADDomainController
Get-DnsServerZone
Get-Service NTDS
Get-Service w32time
w32tm /query /status
w32tm /query /source
```

## Linux / DNS

``` bash
realm discover vgs.com
nslookup dc01.vgs.com
nslookup -type=SRV _ldap._tcp.vgs.com
nslookup -type=SRV _kerberos._tcp.vgs.com
```

## Linux / Time

``` bash
timedatectl
chronyc sources -v
chronyc tracking
```

------------------------------------------------------------------------

# 40. Final Status

The core Active Directory infrastructure has been successfully built.

``` text
Active Directory Domain: vgs.com
Domain Controller:       DC01
DC IP:                   192.168.253.161
Infrastructure DNS:      Technitium DNS (192.168.253.1)
Linux NTP Source:        DC01
Linux AD Discovery:      Working
```

The next phase is:

``` text
Active Directory
        |
        v
Create OUs
        |
        v
Create Groups
        |
        v
Create Users
        |
        v
Linux Authentication
        |
        v
VMware / vCenter Integration
```

**End of Document**
