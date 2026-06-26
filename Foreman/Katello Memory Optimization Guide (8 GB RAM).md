# Foreman/Katello Memory Optimization Guide (8 GB RAM)

## Objective

Optimize memory usage on a Foreman + Katello server with **8 GB RAM** while maintaining the following services:

* Foreman
* Katello
* Content Views
* Activation Keys
* Repository Synchronization
* PXE Provisioning
* Remote Execution
* AWX Integration

---

# Server Information

| Component        | Value                                  |
| ---------------- | -------------------------------------- |
| Operating System | CentOS 7                               |
| RAM              | 8 GB                                   |
| Foreman          | Installed                              |
| Katello          | Installed                              |
| Puppet Server    | Disabled (Not required in current lab) |

---

# Step 1 - Check Current Memory Usage

## Display Memory Usage

```bash
free -h
```

Initial Output

```text
Mem:           7.8G        7.0G        235M
Swap:          3.9G      512K
```

---

## Display Top Memory Consumers

```bash
ps -eo pid,ppid,user,%mem,%cpu,rss,vsz,comm --sort=-%mem | head -10
```

Example Output

```text
Tomcat Java        ~1.36 GB
Sidekiq            ~350 MB x 3
Ruby Workers       ~340 MB x 5
```

---

# Step 2 - Tune Tomcat JVM Heap

## Backup Configuration

```bash
cp /etc/tomcat/tomcat.conf /etc/tomcat/tomcat.conf.bak
```

## Edit Configuration

```bash
vi /etc/tomcat/tomcat.conf
```

Original

```text
JAVA_OPTS="-Xms1024m -Xmx4096m -Dcom.redhat.fips=false"
```

Updated

```text
JAVA_OPTS="-Xms512m -Xmx2048m -Dcom.redhat.fips=false"
```

Restart Tomcat

```bash
systemctl restart tomcat
```

Verify

```bash
systemctl status tomcat
```

---

# Step 3 - Tune Puppet Server JVM

Edit configuration

```bash
vi /etc/sysconfig/puppetserver
```

Original

```text
JAVA_ARGS="-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"
```

Updated

```text
JAVA_ARGS="-Xms512m -Xmx1024m -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"
```

Restart Puppet Server

```bash
systemctl restart puppetserver
```

---

# Step 4 - Determine Whether Puppet Server Is Required

After testing the environment, it was verified that the following Katello features continued to work without Puppet Server:

* Content Views
* Activation Keys
* Repository Synchronization
* Host Registration
* Remote Execution
* AWX Integration

Therefore, Puppet Server was stopped and disabled.

```bash
systemctl stop puppetserver
systemctl disable puppetserver
```

Verify

```bash
systemctl status puppetserver
```

Expected

```text
Loaded: loaded (...; disabled)
Active: inactive (dead)
```

---

# Step 5 - Optimize Foreman Puma

Display Current Configuration

```bash
systemctl cat foreman
```

Original

```text
Environment=FOREMAN_PUMA_THREADS_MIN=5
Environment=FOREMAN_PUMA_THREADS_MAX=5
Environment=FOREMAN_PUMA_WORKERS=5
```

Edit

```bash
vi /etc/systemd/system/foreman.service.d/installer.conf
```

Update

```text
Environment=FOREMAN_PUMA_THREADS_MIN=3
Environment=FOREMAN_PUMA_THREADS_MAX=3
Environment=FOREMAN_PUMA_WORKERS=2
```

Reload Systemd

```bash
systemctl daemon-reload
```

Restart Foreman

```bash
systemctl restart foreman
```

---

# Step 6 - Optimize Sidekiq Concurrency

Check Current Configuration

```bash
grep -R "concurrency" /etc/foreman/dynflow
```

Original

```text
orchestrator.yml
concurrency: 1

worker-1.yml
concurrency: 5

worker-hosts-queue-1.yml
concurrency: 5
```

Edit

```bash
vi /etc/foreman/dynflow/worker-1.yml
```

Change

```yaml
:concurrency: 5
```

To

```yaml
:concurrency: 2
```

Edit

```bash
vi /etc/foreman/dynflow/worker-hosts-queue-1.yml
```

Change

```yaml
:concurrency: 5
```

To

```yaml
:concurrency: 2
```

Restart Foreman

```bash
systemctl restart foreman
```

Verify

```bash
grep concurrency /etc/foreman/dynflow/*.yml
```

Expected

```text
/etc/foreman/dynflow/orchestrator.yml::concurrency: 1
/etc/foreman/dynflow/worker-1.yml::concurrency: 2
/etc/foreman/dynflow/worker-hosts-queue-1.yml::concurrency: 2
```

---

# Step 7 - Verify Final Memory Usage

```bash
free -h
```

Final Output

```text
Mem:           7.8G        5.5G        1.9G
Swap:          3.9G        3.8M
```

---

# Final Memory Comparison

| Stage                   | Used RAM | Available RAM |
| ----------------------- | -------: | ------------: |
| Before Tuning           |  ~7.0 GB |       ~486 MB |
| After JVM Optimization  |  ~6.0 GB |       ~1.4 GB |
| After Puma Optimization |  ~5.5 GB |       ~1.9 GB |

**Approximate Memory Saved:** **1.5 GB**

---

# Final Configuration

## Tomcat

```text
-Xms512m
-Xmx2048m
```

## Puppet Server (Configuration)

```text
-Xms512m
-Xmx1024m
```

> **Note:** Although the JVM configuration was optimized, the Puppet Server service is currently **stopped and disabled** because it is not required for this lab environment.

## Foreman Puma

```text
FOREMAN_PUMA_THREADS_MIN=3
FOREMAN_PUMA_THREADS_MAX=3
FOREMAN_PUMA_WORKERS=2
```

## Sidekiq

```text
Orchestrator              : 1
Worker Queue              : 2
Worker Hosts Queue        : 2
```

---

# Final Verification

Verify memory:

```bash
free -h
```

Verify Tomcat:

```bash
systemctl status tomcat
```

Verify Foreman:

```bash
systemctl status foreman
```

Verify Puppet Server:

```bash
systemctl status puppetserver
```

Verify Sidekiq configuration:

```bash
grep concurrency /etc/foreman/dynflow/*.yml
```

Verify Foreman Puma configuration:

```bash
systemctl cat foreman
```

---

# Final Result

The Foreman/Katello server has been successfully optimized for an **8 GB RAM** environment.

### Achievements

* Reduced Tomcat JVM heap from **4 GB** to **2 GB**
* Reduced Puppet JVM heap from **2 GB** to **1 GB**
* Disabled Puppet Server after confirming it was not required in the current lab
* Reduced Puma workers from **5** to **2**
* Reduced Puma threads from **5** to **3**
* Reduced Sidekiq worker concurrency from **5** to **2**
* Reduced overall memory usage from approximately **7.0 GB** to **5.5 GB**
* Increased available memory from approximately **486 MB** to **1.9 GB**
* Foreman, Katello, Content Views, Activation Keys, Repository Synchronization, PXE Provisioning, Remote Execution, and AWX Integration continue to function normally.
