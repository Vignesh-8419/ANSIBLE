# AWX PostgreSQL Recovery – WAL / Checkpoint Corruption

## Issue Summary

The AWX instance became unavailable because the PostgreSQL database pod failed to start.

## Symptoms

The AWX namespace showed the following pod status:

```text
awx-server-postgres-15-0   CrashLoopBackOff
awx-server-task            Unknown
awx-server-web             CrashLoopBackOff / NotReady
```

The initial PostgreSQL logs only displayed a generic startup failure:

```text
waiting for server to start....
pg_ctl: could not start server
Examine the log output.
```

---

# Root Cause

After examining the PostgreSQL internal log files, the actual error was:

```text
database system was interrupted
invalid record length at 0/57DF118: wanted 24, got 0
invalid primary checkpoint record
PANIC: could not locate a valid checkpoint record
startup process was terminated by signal 6: Aborted
database system is shut down
```

---

# Cause Analysis

The PostgreSQL database directory was verified and found to be intact.

Verified components:

- PG_VERSION
- pg_control
- base/
- global/
- pg_wal/
- postgresql.conf
- Correct ownership (UID 26 / GID 26)

This confirmed that the database itself was **not deleted or corrupted**.

The failure was caused by corruption of the PostgreSQL **Write-Ahead Log (WAL)** checkpoint metadata.

During startup PostgreSQL performs crash recovery by reading the latest checkpoint stored in the WAL.

Since the checkpoint record itself was corrupted, PostgreSQL refused to start in order to prevent additional database corruption.

### Possible Causes

- Unexpected server shutdown
- Power failure
- Host reboot while PostgreSQL was writing
- Forced Kubernetes pod termination
- Storage interruption
- Filesystem corruption
- Disk corruption
- Kubernetes node crash

In this case:

- PVC was healthy.
- Database files existed.
- PostgreSQL version matched (15).
- Permissions were correct.
- Only WAL/checkpoint metadata was corrupted.

Therefore the database was recoverable without deleting the PVC.

---

# Recovery Procedure

## Step 1 – Verify AWX Pods

Check the AWX namespace.

```bash
kubectl get pods -n awx
```

Output:

```text
awx-server-postgres-15-0   CrashLoopBackOff
awx-server-task            Unknown
awx-server-web             CrashLoopBackOff
```

---

## Step 2 – Check PostgreSQL Logs

```bash
kubectl logs -n awx awx-server-postgres-15-0
```

Output:

```text
waiting for server to start....
pg_ctl: could not start server
Examine the log output.
```

No useful error was shown.

---

## Step 3 – Verify Persistent Volume Claim

```bash
kubectl get pvc -n awx
```

Output:

```text
NAME                                   STATUS
postgres-15-awx-server-postgres-15-0   Bound
```

PVC was healthy.

---

## Step 4 – Locate the Persistent Volume

```bash
kubectl get pv pvc-97c54158-1afd-4fe1-862a-b069c3b172c7 -o yaml
```

The PV pointed to:

```text
/var/lib/rancher/k3s/storage/pvc-97c54158-1afd-4fe1-862a-b069c3b172c7_awx_postgres-15-awx-server-postgres-15-0
```

---

## Step 5 – Verify PostgreSQL Files

```bash
cd /var/lib/rancher/k3s/storage/pvc-97c54158-1afd-4fe1-862a-b069c3b172c7_awx_postgres-15-awx-server-postgres-15-0
```

Verify directory.

```bash
pwd
```

List contents.

```bash
ls -lah
```

```bash
ls -lah data
```

```bash
ls -lah data/userdata
```

Verify PostgreSQL version.

```bash
cat data/userdata/PG_VERSION
```

Output:

```text
15
```

Verified:

- PG_VERSION
- pg_control
- pg_wal
- global
- base
- postgresql.conf

---

## Step 6 – Read PostgreSQL Internal Logs

Read PostgreSQL log files.

```bash
for f in data/userdata/log/*; do
    echo "===== $f ====="
    tail -100 "$f"
done
```

This exposed the actual error.

```text
database system was interrupted

invalid record length

invalid primary checkpoint record

PANIC:
could not locate a valid checkpoint record
```

At this point the issue was confirmed to be WAL corruption.

---

## Step 7 – Backup PostgreSQL Data

Before attempting any repair, create a complete backup.

```bash
cd /var/lib/rancher/k3s/storage
```

```bash
cp -a \
pvc-97c54158-1afd-4fe1-862a-b069c3b172c7_awx_postgres-15-awx-server-postgres-15-0 \
pvc-97c54158-1afd-4fe1-862a-b069c3b172c7_backup
```

---

## Step 8 – Stop the AWX Operator

Prevent the operator from recreating PostgreSQL during recovery.

```bash
kubectl scale deployment awx-operator-controller-manager \
--replicas=0 \
-n awx
```

---

## Step 9 – Delete Failed PostgreSQL Pod

```bash
kubectl delete pod awx-server-postgres-15-0 \
-n awx \
--force \
--grace-period=0
```

---

## Step 10 – Create PostgreSQL Recovery Pod

Create the file.

```bash
vi pg-recovery.yaml
```

Contents:

```yaml
apiVersion: v1
kind: Pod

metadata:
  name: pg-recovery
  namespace: awx

spec:
  restartPolicy: Never

  containers:
    - name: recovery
      image: quay.io/sclorg/postgresql-15-c9s:latest
      command:
        - sleep
        - infinity

      volumeMounts:
        - name: pgdata
          mountPath: /var/lib/pgsql/data

  volumes:
    - name: pgdata
      persistentVolumeClaim:
        claimName: postgres-15-awx-server-postgres-15-0
```

Deploy:

```bash
kubectl apply -f pg-recovery.yaml
```

Wait until the pod becomes Ready.

```bash
kubectl wait \
--for=condition=Ready \
pod/pg-recovery \
-n awx \
--timeout=120s
```

---

## Step 11 – Access Recovery Pod

```bash
kubectl exec -it -n awx pg-recovery -- sh
```

---

## Step 12 – Locate Correct PostgreSQL Directory

List mounted files.

```bash
ls -lah /var/lib/pgsql/data
```

Find database files.

```bash
find /var/lib/pgsql/data -maxdepth 3 -type f
```

Actual database path:

```text
/var/lib/pgsql/data/data/userdata
```

The additional **data/** directory exists because the original StatefulSet mounted the PVC using:

```yaml
subPath: data
```

---

## Step 13 – Verify PostgreSQL Control File

Run:

```bash
pg_controldata \
/var/lib/pgsql/data/data/userdata
```

The control file was successfully read.

---

## Step 14 – Reset WAL

Repair the WAL.

```bash
pg_resetwal -f \
/var/lib/pgsql/data/data/userdata
```

This recreated the checkpoint metadata.

Exit recovery shell.

```bash
exit
```

---

## Step 15 – Delete Recovery Pod

```bash
kubectl delete pod pg-recovery -n awx
```

---

## Step 16 – Restart AWX Operator

```bash
kubectl scale deployment awx-operator-controller-manager \
--replicas=1 \
-n awx
```

---

## Step 17 – Monitor Recovery

```bash
kubectl get pods -n awx -w
```

Recovery sequence:

```text
PostgreSQL

↓

Running

↓

Web

↓

Running

↓

Task

↓

Running
```

---

## Step 18 – Verify Final Status

```bash
kubectl get pods -n awx
```

Healthy output:

```text
NAME                                               READY   STATUS
awx-operator-controller-manager                    2/2     Running
awx-server-postgres-15-0                           1/1     Running
awx-server-web                                     3/3     Running
awx-server-task                                    4/4     Running
awx-server-migration                               0/1     Completed
```

---

## Step 19 – Verify PostgreSQL Logs

```bash
kubectl logs -n awx awx-server-postgres-15-0
```

Expected:

```text
database system is ready to accept connections
```

---

# Resolution

The PostgreSQL database was successfully recovered **without deleting the PVC**.

The recovery process consisted of:

1. Identifying the actual PostgreSQL startup error.
2. Verifying the database files were intact.
3. Backing up the PostgreSQL data directory.
4. Creating a temporary recovery pod using the same PostgreSQL 15 image.
5. Running `pg_resetwal` to rebuild the corrupted WAL/checkpoint metadata.
6. Restarting the AWX Operator.
7. Confirming PostgreSQL, AWX Web, and AWX Task pods returned to the **Running** state.

This approach preserved the existing AWX database and avoided rebuilding the AWX environment or losing application data.
