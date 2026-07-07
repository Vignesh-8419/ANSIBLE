# PostgreSQL WAL Corruption Recovery SOP (NetBox Recovery)

## Scenario

NetBox displayed the following error:

```
django.db.utils.OperationalError

connection failed:
connection to server at "127.0.0.1", port 5432 failed:
Connection refused
```

PostgreSQL service failed to start.

---

# Root Cause

The PostgreSQL Write Ahead Log (WAL) became corrupted.

PostgreSQL log showed:

```
unexpected pageaddr 0/20C4000 in log segment 000000010000000000000004

invalid primary checkpoint record

PANIC: could not locate a valid checkpoint record
```

This indicates PostgreSQL could not locate a valid checkpoint in the WAL and therefore could not recover automatically.

**Important**

The database itself was NOT corrupted.

Only the WAL/checkpoint metadata was corrupted.

`pg_resetwal` is intended as a **last-resort** recovery tool for this situation. After using it, PostgreSQL recommends taking an immediate logical backup (`pg_dump`/`pg_dumpall`), rebuilding a fresh cluster, and restoring from that backup. :contentReference[oaicite:0]{index=0}

---

# Step 1 - Verify PostgreSQL Status

```bash
systemctl status postgresql-15
```

If failed:

```bash
journalctl -u postgresql-15 --no-pager -n 100
```

---

# Step 2 - Check PostgreSQL Logs

```bash
tail -100 /var/lib/pgsql/15/data/log/*
```

Expected error:

```
PANIC:
could not locate a valid checkpoint record
```

---

# Step 3 - Stop PostgreSQL

```bash
systemctl stop postgresql-15
```

Verify no postgres processes exist.

```bash
ps -ef | grep postgres
```

Expected:

```
only grep process
```

---

# Step 4 - Preserve Existing Data

Rename the existing data directory.

```bash
mv /var/lib/pgsql/15/data \
   /var/lib/pgsql/15/data.broken.$(date +%F_%H%M)
```

If you accidentally initialized a new PostgreSQL cluster:

```
data
data.broken
```

Rename them back:

```bash
mv /var/lib/pgsql/15/data \
   /var/lib/pgsql/15/data.new

mv /var/lib/pgsql/15/data.broken.YYYY-MM-DD_HHMM \
   /var/lib/pgsql/15/data
```

Fix ownership.

```bash
chown -R postgres:postgres /var/lib/pgsql/15/data
```

---

# Step 5 - Verify Cluster Metadata

Switch to postgres user.

```bash
su - postgres
```

Run:

```bash
/usr/pgsql-15/bin/pg_controldata /var/lib/pgsql/15/data
```

Verify:

```
Database cluster state

Latest checkpoint

Latest checkpoint REDO

Latest checkpoint WAL file
```

---

# Step 6 - Verify WAL Files

```bash
ls -lh /var/lib/pgsql/15/data/pg_wal
```

Example:

```
000000010000000000000004
000000010000000000000005
```

---

# Step 7 - Backup Current Cluster

Always create another copy before resetting WAL.

```bash
cp -a \
/var/lib/pgsql/15/data \
/var/lib/pgsql/15/data.pre_pgresetwal
```

---

# Step 8 - Dry Run pg_resetwal

```bash
/usr/pgsql-15/bin/pg_resetwal -n \
/var/lib/pgsql/15/data
```

Expected:

```
Values to be changed

First WAL segment after reset
```

No changes are made.

---

# Step 9 - Force WAL Reset

Run as postgres user.

```bash
/usr/pgsql-15/bin/pg_resetwal -f \
/var/lib/pgsql/15/data
```

Expected:

```
Write-ahead log reset
```

---

# Step 10 - Start PostgreSQL

Exit postgres user.

```bash
exit
```

Start PostgreSQL.

```bash
systemctl start postgresql-15
```

Verify.

```bash
systemctl status postgresql-15
```

Expected:

```
Active: active (running)
```

---

# Step 11 - Backup Immediately

After recovery immediately create a logical backup.

Entire cluster:

```bash
sudo -u postgres pg_dumpall > \
/root/postgresql_recovered.sql
```

Database only:

```bash
sudo -u postgres pg_dump \
-Fc netbox \
> /root/netbox.dump
```

---

# Step 12 - Verify Database Exists

```bash
sudo -u postgres psql -l
```

Expected:

```
netbox
postgres
template0
template1
```

---

# Step 13 - Connect to NetBox Database

```bash
sudo -u postgres psql
```

```
\c netbox
```

Verify tables.

```
\dt
```

Expected:

```
189 tables
```

Example:

```
dcim_device

ipam_prefix

users_user

extras_tag
```

---

# Step 14 - Verify Django Migrations

```sql
SELECT COUNT(*) FROM django_migrations;
```

or

```bash
sudo -u postgres \
psql \
-d netbox \
-c "SELECT COUNT(*) FROM django_migrations;"
```

---

# Step 15 - Verify NetBox Database Configuration

```bash
grep -A10 DATABASE \
/opt/netbox/netbox/netbox/configuration.py
```

Verify:

```
NAME

USER

PASSWORD

HOST

PORT
```

---

# Step 16 - Restart NetBox

```bash
systemctl restart netbox
systemctl restart netbox-rq
systemctl restart httpd
```

or

```bash
systemctl restart nginx
```

---

# Step 17 - Verify Services

```bash
systemctl status netbox
```

```bash
systemctl status netbox-rq
```

```bash
systemctl status postgresql-15
```

---

# Step 18 - Verify NetBox UI

Open:

```
http://<server-ip>

or

https://<server-ip>
```

Confirm:

- Login page loads
- Existing devices exist
- Existing IPs exist
- Existing Tags exist
- Existing Config Contexts exist

---

# Recovery Summary

| Step | Status |
|-------|--------|
| PostgreSQL Failed | ✅ |
| WAL Corruption Identified | ✅ |
| Original Cluster Preserved | ✅ |
| pg_controldata Verified | ✅ |
| WAL Reset Performed | ✅ |
| PostgreSQL Started | ✅ |
| NetBox Database Recovered | ✅ |
| 189 Tables Verified | ✅ |
| Logical Backup Created | ✅ |

---

# Root Cause

The PostgreSQL WAL became corrupted.

```
PANIC:
could not locate a valid checkpoint record
```

The actual NetBox data remained intact.

The WAL metadata was rebuilt using:

```
pg_resetwal -f
```

allowing PostgreSQL to start successfully.

---

# Recommended Best Practices

- Schedule daily `pg_dump` backups.
- Enable WAL archiving for point-in-time recovery if this is a production system.
- Avoid powering off the VM abruptly.
- Monitor disk health and filesystem integrity.
- Test restores periodically to ensure backups are usable. :contentReference[oaicite:1]{index=1}
