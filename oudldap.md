Sorry da, puriyudhu. You want everything in ONE single code block, including all commands, configurations, LDIF files and notes — not separate code blocks inside the Markdown.

```
# Oracle Unified Directory (OUD) – Complete LDAP Configuration

## 1. Java Environment Setup

export JAVA_HOME=/usr/jdk/jdk1.8.0_311
export PATH=$JAVA_HOME/bin:$PATH
java -version

export PATH=$PATH:/export/home/ldapadm/Oracle/Middleware/Oracle_Home/oud/
export PATH=$PATH:/export/home/ldapadm/Oracle/Middleware/Oracle_Home/asinst_1/

## 2. OUD Installation

unzip V983402-01.zip

java -jar fmw_12.2.1.3.0_oud.jar
java -jar fmw_12.2.1.4.0_oud.jar
java -jar fmw_12.2.1.4.0_oud.jar -ignoreSysPrereqs

cd /export/home/ldapadm/Oracle/Middleware/Oracle_Home/oud/
./oud-setup
/usr/sbin/ldapservercfg oud

## 3. LDAP Server Details

LDAP Server: 192.168.253.160
LDAP Port: 1389
Base DN: dc=vs,dc=com

## 4. LDAP Search Commands

nslookup oudldap

ldapsearch -x -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -b "dc=vs,dc=com" "(objectclass=*)"

ldapsearch -x -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -b "dc=prod,dc=vs,dc=com" "(objectclass=*)"

ldapsearch -x -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -b "ou=people,dc=prod,dc=vs,dc=com" "(uid=*)"

ldapsearch -x -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -b "cn=proxyagent,ou=profile,dc=prod,dc=vs,dc=com" "(uid=*)"

## 5. LDAP Directory Structure

### Production Domain

dn: dc=prod,dc=vs,dc=com
objectClass: top
objectClass: domain
dc: prod

dn: ou=people,dc=prod,dc=vs,dc=com
objectClass: top
objectClass: organizationalUnit
ou: people

dn: ou=group,dc=prod,dc=vs,dc=com
objectClass: top
objectClass: organizationalUnit
ou: group

### Development Domain

dn: dc=dev,dc=vs,dc=com
objectClass: top
objectClass: domain
dc: dev

dn: ou=people,dc=dev,dc=vs,dc=com
objectClass: top
objectClass: organizationalUnit
ou: people

dn: ou=group,dc=dev,dc=vs,dc=com
objectClass: top
objectClass: organizationalUnit
ou: group

### Test Domain

dn: dc=test,dc=vs,dc=com
objectClass: top
objectClass: domain
dc: test

dn: ou=people,dc=test,dc=vs,dc=com
objectClass: top
objectClass: organizationalUnit
ou: people

dn: ou=group,dc=test,dc=vs,dc=com
objectClass: top
objectClass: organizationalUnit
ou: group

### Create Directory Structure

ldapadd -h 192.168.253.161 -p 1389 -D "cn=Directory Manager" -w Simple@123 -f create_test_domain.ldif

## 6. LDAP User Creation

### Production User

dn: uid=orad2,ou=people,dc=prod,dc=vs,dc=com
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
uid: orad2
cn: New User
sn: User
userPassword: orad2@123
uidNumber: 1002
gidNumber: 1002
homeDirectory: /export/home/orad2

### Development User

dn: uid=orafe,ou=people,dc=dev,dc=vs,dc=com
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
cn: orafe
sn: user
uid: orafe
uidNumber: 1004
gidNumber: 1004
homeDirectory: /export/home/orafe
loginShell: /bin/bash
userPassword: newpassword

### Add LDAP Users

ldapadd -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f orad2.ldif

ldapadd -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f orafe.ldif

## 7. LDAP Group Creation

dn: cn=orad2,ou=group,dc=prod,dc=vs,dc=com
objectClass: top
objectClass: posixGroup
cn: orad2
gidNumber: 1002
memberUid: orad2

### Add Group

ldapadd -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f prodgroup.ldif

## 8. Proxy Agent Creation

dn: cn=proxyagent,ou=profile,dc=prod,dc=vs,dc=com
objectClass: top
objectClass: person
cn: proxyagent
sn: proxyagent
userPassword: {SSHA}examplePasswordHash

### Add Proxy Agent

ldapadd -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f testproxy.ldif

### Modify Proxy Agent Password

dn: cn=proxyagent,ou=profile,dc=prod,dc=vs,dc=com
changetype: modify
replace: userPassword
userPassword: newpassword

ldapmodify -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f solaris11_profile.ldif

## 9. Solaris 11 LDAP Client Configuration

### Manual Configuration

ldapclient manual \
-a authenticationMethod=none \
-a defaultSearchBase=dc=dev,dc=vs,dc=com \
-a domainName=vs.com \
-a preferredServerList=192.168.253.160:1389 \
-a proxyDN=cn=proxyagent,ou=people,dc=dev,dc=vs,dc=com \
-a proxyPassword=newpassword \
-a serviceSearchDescriptor=passwd:ou=people,dc=dev,dc=vs,dc=com

### Simple Authentication

ldapclient manual \
-a authenticationMethod=simple \
-a defaultSearchBase=dc=dev,dc=vs,dc=com \
-a domainName=vs.com \
-a preferredServerList=192.168.253.160:1389 \
-a proxyDN=cn=proxyagent,ou=people,dc=dev,dc=vs,dc=com \
-a proxyPassword=newpassword \
-a serviceSearchDescriptor=passwd:ou=people,dc=dev,dc=vs,dc=com

### TLS Authentication

ldapclient manual \
-a authenticationMethod=tls:simple \
-a defaultSearchBase=dc=dev,dc=vs,dc=com \
-a domainName=vs.com \
-a preferredServerList=192.168.253.160:1636 \
-a proxyDN=cn=proxyagent,ou=people,dc=dev,dc=vs,dc=com \
-a proxyPassword=newpassword \
-a serviceSearchDescriptor=passwd:ou=people,dc=dev,dc=vs,dc=com

### Initialize LDAP Client Using Profile

ldapclient init \
-a proxyDN="cn=proxyagent,ou=profile,dc=prod,dc=vs,dc=com" \
-a domainname=vs.com \
-a profilename=solaris_11 \
-a proxypassword=Proxy@123 \
192.168.253.161:1389

### Check LDAP Client Configuration

ldapclient list

Example output:

NS_LDAP_FILE_VERSION= 2.0
NS_LDAP_BINDDN= cn=proxyagent,ou=people,dc=dev,dc=vs,dc=com
NS_LDAP_BINDPASSWD= {NS1}6837c9c206c5c5c2e3a45e
NS_LDAP_SEARCH_BASEDN= dc=dev,dc=vs,dc=com
NS_LDAP_AUTH= simple
NS_LDAP_SERVER_PREF= 192.168.253.160:1389
NS_LDAP_CACHETTL= 0
NS_LDAP_SERVICE_SEARCH_DESC= passwd:ou=people,dc=dev,dc=vs,dc=com

## 10. Solaris LDAP Profile Configuration

### solaris11_profile.ldif

dn: cn=solaris_11,ou=profile,dc=vs,dc=com
objectClass: top
objectClass: DUAConfigProfile
cn: solaris
defaultServerList: 192.168.253.161:1389
defaultSearchBase: dc=prod,dc=vs,dc=com
authenticationMethod: none
credentialLevel: proxy
defaultSearchScope: one
bindTimeLimit: 10
searchTimeLimit: 30
profileTTL: 43200

### Add Profile

ldapadd -h 192.168.253.161 -p 1389 -D "cn=Directory Manager" -w Simple@123 -f solaris11_profile.ldif

## 11. LDAP Password Modification

dn: uid=orafe,ou=people,dc=dev,dc=vs,dc=com
changetype: modify
replace: userPassword
userPassword: {SSHA}MVMWWchRgrRZOdvm18QjdvrUStJ4CT1p

### Apply Password Changes

ldapmodify -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f passtest.ldif

## 12. Adding shadowAccount Attributes

### modify_shadow.ldif

dn: uid=orad2,ou=people,dc=prod,dc=vs,dc=com
changetype: modify
add: objectClass
objectClass: shadowAccount
-
add: shadowLastChange
shadowLastChange: 18000
-
add: shadowMin
shadowMin: 0
-
add: shadowMax
shadowMax: 99999
-
add: shadowWarning
shadowWarning: 7

### Apply Changes

ldapmodify -h 192.168.253.161 -p 1389 -D "cn=Directory Manager" -w Simple@123 -f modify_shadow.ldif

## 13. LDAP Access Control Instructions (ACI)

### modify_aci.ldif

dn: ou=people,dc=prod,dc=vs,dc=com
changetype: modify
add: aci
aci: (targetattr="*")(version 3.0; acl "Allow Read"; allow (read, search, compare) userdn="ldap:///anyone";)

### Apply ACI

ldapmodify -h 192.168.253.161 -p 1389 -D "cn=Directory Manager" -w Simple@123 -f modify_aci.ldif

## 14. RHEL 7 SSSD Configuration

### /etc/sssd/sssd.conf

[sssd]
config_file_version = 2
domains = vs.com

[domain/vs.com]
debug_level = 9
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://192.168.253.161:1389
ldap_search_base = dc=vs,dc=com
ldap_user_search_base = ou=people,dc=prod,dc=vs,dc=com
ldap_group_search_base = ou=group,dc=prod,dc=vs,dc=com
ldap_default_bind_dn = cn=Directory Manager,dc=vs,dc=com
ldap_tls_reqcert = never
ldap_default_authtok_type = password
ldap_default_authtok = Simple@123

### /etc/pam.d/system-auth

#%PAM-1.0

auth required pam_env.so
auth sufficient pam_unix.so nullok try_first_pass
auth requisite pam_succeed_if.so uid >= 500 quiet
auth sufficient pam_sss.so use_first_pass
auth required pam_deny.so

account required pam_unix.so
account sufficient pam_localuser.so
account sufficient pam_succeed_if.so uid < 500 quiet
account [default=bad success=ok user_unknown=ignore] pam_sss.so
account required pam_permit.so

password requisite pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password sufficient pam_unix.so sha512 shadow nullok try_first_pass use_authtok
password sufficient pam_sss.so use_authtok
password required pam_deny.so

session optional pam_keyinit.so revoke
session required pam_limits.so
-session optional pam_systemd.so
session [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session required pam_unix.so
session optional pam_sss.so

### /etc/pam.d/password-auth

#%PAM-1.0

auth required pam_env.so
auth sufficient pam_unix.so nullok try_first_pass
auth requisite pam_succeed_if.so uid >= 500 quiet
auth sufficient pam_sss.so use_first_pass
auth required pam_deny.so

account required pam_unix.so
account sufficient pam_localuser.so
account sufficient pam_succeed_if.so uid < 500 quiet
account [default=bad success=ok user_unknown=ignore] pam_sss.so
account required pam_permit.so

password requisite pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password sufficient pam_unix.so sha512 shadow nullok try_first_pass use_authtok
password sufficient pam_sss.so use_authtok
password required pam_deny.so

session optional pam_keyinit.so revoke
session required pam_limits.so
-session optional pam_systemd.so
session [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session required pam_unix.so
session optional pam_sss.so

## 15. SSH PAM Configuration

### /etc/pam.d/sshd

auth required pam_env.so
auth sufficient pam_unix.so try_first_pass
auth sufficient pam_sss.so use_first_pass
auth required pam_deny.so

account required pam_unix.so
account sufficient pam_sss.so
account required pam_deny.so

password required pam_unix.so
password sufficient pam_sss.so
password required pam_deny.so

session required pam_limits.so
session required pam_unix.so
session optional pam_sss.so
session required pam_mkhomedir.so skel=/etc/skel/ umask=0022

## 16. Solaris PAM Configuration

### /etc/pam.d/sshd

auth required pam_env.so
auth required pam_shells.so
auth requisite pam_nologin.so
auth sufficient pam_ldap.so use_first_pass
auth sufficient pam_unix.so try_first_pass
auth required pam_deny.so

account sufficient pam_ldap.so
account required pam_unix.so

password sufficient pam_ldap.so
password sufficient pam_unix.so
password required pam_deny.so

session required pam_limits.so
session required pam_unix.so
session optional pam_ldap.so
session required pam_mkhomedir.so skel=/etc/skel/ umask=0022

### /etc/pam.conf

# The libpam library searches for PAM entries in the following order:
# /etc/pam.conf for service entries
# /etc/pam.d/<service>
# /etc/pam.conf for "other" entries
# /etc/pam.d/other

### /etc/pam.d/other

auth definitive pam_user_policy.so.1
auth requisite pam_authtok_get.so.1
auth required pam_unix_auth.so.1
auth required pam_unix_cred.so.1

account requisite pam_roles.so.1
account definitive pam_user_policy.so.1
account required pam_unix_account.so.1
account required pam_tsol_account.so.1

session definitive pam_user_policy.so.1
session required pam_unix_session.so.1
session optional pam_fm_notify.so.1

password definitive pam_user_policy.so.1
password include pam_authtok_common
password required pam_authtok_store.so.1

### /etc/pam.d/sshd-password

auth definitive pam_user_policy.so.1
auth required pam_unix_auth.so.1
auth required pam_unix_cred.so.1 noannotation

## 17. Solaris Audit Syslog Configuration

auditconfig -setplugin audit_syslog active p_flags=lo,+as,-ss

vi /etc/syslog.conf

Add:

audit.notice /var/adm/auditlog

touch /var/adm/auditlog
chmod 640 /var/adm/auditlog

svcs system-log
svcadm refresh system/system-log:default
audit -s

## 18. OUD Trust Manager and StartTLS Configuration

### Create Trust Manager Provider

./dsconfig create-trust-manager-provider \
--provider-name "TrustManager" \
--type file-based \
--set trust-store-file:/export/home/ldapadm/Oracle/Middleware/Oracle_Home/asinst_1/OUD/config/truststore

### Configure LDAP Connection Handler

./dsconfig set-connection-handler-prop \
--handler-name "LDAP Connection Handler" \
--set key-manager-provider:JKS \
--set trust-manager-provider:TrustManager \
--set allow-start-tls:true

### Restart OUD

./stop-ds
./start-ds

### Solaris TLS Client Configuration

ldapclient manual \
-a authenticationMethod=tls:simple \
-a defaultSearchBase=dc=dev,dc=vs,dc=com \
-a domainName=vs.com \
-a preferredServerList=192.168.253.160:1636 \
-a proxyDN=cn=proxyagent,ou=people,dc=dev,dc=vs,dc=com \
-a proxyPassword=newpassword \
-a serviceSearchDescriptor=passwd:ou=people,dc=dev,dc=vs,dc=com

## 19. OUD Replication Configuration

dsreplication enable \
--host1 <source-host> \
--port1 4444 \
--bindDN1 "cn=Directory Manager" \
--bindPassword1 Simple@123 \
--host2 <target-host> \
--port2 4444 \
--bindDN2 "cn=Directory Manager" \
--bindPassword2 Simple@123 \
--replicationPort1 8989 \
--replicationPort2 8989 \
--baseDN "dc=vs,dc=com" \
--adminUID admin \
--adminPassword <admin-password> \
--secureReplication \
--trustAll \
--no-prompt

## 20. OUD Password Storage Scheme

### Check Default Password Policy

dsconfig get-password-policy-prop \
--policy-name "Default Password Policy" \
--advanced

### Change Password Storage Scheme

dsconfig set-password-policy-prop \
--policy-name "Default Password Policy" \
--set default-password-storage-scheme:<scheme>

### Example: CRYPT

dsconfig set-password-policy-prop \
--policy-name "Default Password Policy" \
--set default-password-storage-scheme:CRYPT

## 21. LDAP User Verification

ldapsearch -x -h 192.168.253.161 -p 1389 -D "cn=Directory Manager" -w Simple@123 -b "dc=vs,dc=com" "(uid=orad2)"

getent passwd

ssh orad2@testunix01.vs.com

## 22. OUD Logs

cd Oracle/Middleware/Oracle_Home/asinst_1/OUD/logs/
ls -lrth
tail -f access.log

## 23. Useful LDAP Commands

### Search All LDAP Entries

ldapsearch -x -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -b "dc=vs,dc=com" "(objectclass=*)"

### Search Production Users

ldapsearch -x -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -b "ou=people,dc=prod,dc=vs,dc=com" "(uid=*)"

### Add LDAP Entry

ldapadd -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f filename.ldif

### Modify LDAP Entry

ldapmodify -h 192.168.253.160 -p 1389 -D "cn=Directory Manager" -w ldap@123 -f filename.ldif

### Check LDAP Client Configuration

ldapclient list

### Modify LDAP Client Authentication

ldapclient mod -a authenticationMethod=simple

### Check System Users

getent passwd

### Monitor OUD Logs

tail -f access.log

## 24. Important Configuration Notes

- LDAP server addresses used in the notes: 192.168.253.160 and 192.168.253.161.
- LDAP ports used: 1389, 1636 and 20002.
- Directory suffixes: dc=vs,dc=com; dc=prod,dc=vs,dc=com; dc=dev,dc=vs,dc=com; dc=test,dc=vs,dc=com.
- Proxy agent DNs vary between examples. Confirm the configured DN before using client commands.
- Solaris profile DN: cn=solaris_11,ou=profile,dc=vs,dc=com.
- Authentication methods shown: none, simple and tls:simple.
- RHEL SSSD examples use LDAP identity and authentication providers.
- PAM examples are specific to the operating systems shown.
- Replication uses placeholders for source and target hosts.
- Password storage scheme example uses CRYPT.

## 25. Security Reminder

The examples contain sample passwords and password hashes. Replace them with secure credentials before production use.

Avoid passing passwords directly in command-line arguments because they may be exposed in shell history and process listings.
```
