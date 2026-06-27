# JVM SIGILL / Candlepin Unreachable Troubleshooting

## Issue

Foreman UI displayed:

```
Oops, we're sorry but something went wrong.
A backend service [ Candlepin ] is unreachable.
```

Tomcat service was repeatedly failing with:

```
code=killed, status=6/ABRT
```

---

# Environment

| Component        | Version                       |
| ---------------- | ----------------------------- |
| OS               | CentOS Linux 7.9              |
| Kernel           | 3.10.0-1160.119.1.el7         |
| Hypervisor       | VMware                        |
| Virtual Hardware | VMware7,1                     |
| CPU              | Intel 11th Gen Core i5-11400H |
| JVM              | OpenJDK 11.0.23               |
| Tomcat           | Apache Tomcat                 |
| Application      | Foreman / Katello / Candlepin |

---

# Symptoms

* Foreman UI reported Candlepin as unreachable.
* Tomcat service terminated with `SIGABRT`.
* ABRT detected Java crashes.
* Multiple JVM fatal error logs were generated:

  * `/usr/share/tomcat/hs_err_pid1374.log`
  * `/usr/share/tomcat/hs_err_pid12128.log`

---

# Troubleshooting Performed

## 1. Verified Tomcat Status

```bash
systemctl status tomcat
systemctl start tomcat
```

Tomcat started successfully, but later crashed again.

---

## 2. Verified Candlepin Deployment

Observed in Tomcat logs:

```
Deploying web application directory /var/lib/tomcat/webapps/candlepin
```

Candlepin deployed correctly before the JVM crash.

---

## 3. Checked ABRT Reports

```bash
abrt-cli list
abrt-cli info -d /var/spool/abrt/ccpp-2026-06-28-04:03:17-12128
```

Result:

```
reason:
java killed by SIGABRT
```

---

## 4. Located JVM Crash Logs

```bash
find / -name "hs_err_pid*.log"
```

Result:

```
/usr/share/tomcat/hs_err_pid1374.log
/usr/share/tomcat/hs_err_pid12128.log
```

---

## 5. Examined JVM Fatal Error

```
A fatal error has been detected by the Java Runtime Environment

SIGILL (Illegal Instruction)

Problematic frame:

J 2200 c1
java.nio.file.attribute.FileTime.<init>()
```

This indicates the JVM crashed while executing JIT-compiled Java code.

---

## 6. Verified Java Installation

Checked Java versions:

```bash
java -version
/usr/lib/jvm/jre-11/bin/java -version
```

Result:

* System default Java: OpenJDK 8
* Tomcat Java: OpenJDK 11.0.23

Verified package integrity:

```bash
rpm -V java-11-openjdk java-11-openjdk-headless
```

No modified or corrupted files were found.

---

## 7. Verified Tomcat Configuration

Checked Java configuration:

```bash
grep -n "JAVA_OPTS\|JAVA_HOME" /etc/tomcat/tomcat.conf
```

Current configuration:

```bash
JAVA_HOME="/usr/lib/jvm/jre-11"
JAVA_OPTS="-Xms1024m -Xmx4096m -Dcom.redhat.fips=false"
```

---

## 8. Verified CPU and Hypervisor

```bash
lscpu
```

Environment:

* VMware virtual machine
* Intel 11th Gen CPU
* AVX512 instruction set exposed

---

# Analysis

The crash is **not caused by**:

* Candlepin
* Tomcat
* Foreman
* Out-of-memory
* Corrupted Java installation

The JVM crashed with:

```
SIGILL (Illegal Instruction)
```

inside JIT-compiled Java code.

This strongly indicates a compatibility issue involving:

* OpenJDK 11 JIT compiler
* VMware virtual CPU presentation
* Modern Intel CPU instruction sets
* Older CentOS 7 kernel

---

# Recommended Fix

Reduce JVM optimization and heap size.

Edit:

```bash
vi /etc/tomcat/tomcat.conf
```

Change:

```bash
JAVA_OPTS="-Xms1024m -Xmx4096m -Dcom.redhat.fips=false"
```

to:

```bash
JAVA_OPTS="-Xms1024m -Xmx2048m -Dcom.redhat.fips=false -XX:TieredStopAtLevel=1"
```

Restart Tomcat:

```bash
systemctl restart tomcat
systemctl status tomcat
```

---

# Diagnostic Test (if issue persists)

Disable the JVM JIT compiler temporarily:

```bash
JAVA_OPTS="-Xms1024m -Xmx2048m -Dcom.redhat.fips=false -Xint"
```

Restart Tomcat.

If the JVM remains stable, this confirms the issue is related to JIT compilation.

---

# Additional Recommendations

1. Update VMware virtual hardware if possible.
2. Review VMware CPU compatibility/EVC settings.
3. Limit exposure of AVX-512 instructions if supported by the hypervisor.
4. Update OpenJDK 11 to the latest available release.
5. Consider migrating the server to Rocky Linux 8/9 for improved compatibility with modern CPUs.

---

# Conclusion

The Foreman message:

```
A backend service [ Candlepin ] is unreachable.
```

was a **secondary symptom**.

The primary issue is a **JVM SIGILL (Illegal Instruction) crash** occurring in JIT-compiled Java code on a VMware virtual machine running CentOS 7 with OpenJDK 11. Stabilizing the JVM resolves the Candlepin availability issue.
