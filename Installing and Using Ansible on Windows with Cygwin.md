# SOP: Installing and Using Ansible on Windows with Cygwin

## 1. Purpose

This SOP documents the complete process for installing and running Ansible from Cygwin on Windows and managing Linux servers through SSH using password authentication.

This document also covers the issues encountered and the fixes:

- Installing Cygwin dependencies
- Installing Python and Ansible
- Running Ansible from Cygwin
- SSH password authentication
- SSH ControlMaster issue in Cygwin
- Managing Linux servers without Python
- Installing Python remotely using the Ansible raw module
- Python 3.6 compatibility issue
- Ansible Core 2.21 incompatibility with Python 3.6
- Installing Ansible Core 2.16.19
- Inventory configuration
- Testing connectivity
- Vim runtime issue encountered in Cygwin
- Final recommended configuration

---

# 2. Environment

## 2.1 Ansible Control Node

| Component | Details |
|---|---|
| Operating System | Windows |
| Unix Environment | Cygwin |
| Ansible User | vigne |
| Ansible Execution | Cygwin terminal |
| Authentication | SSH password authentication |
| Control Node Python | Python 3.12.12 |
| Ansible Version | Ansible Core 2.16.19 |

Example Cygwin prompt:

```text
vigne@DESKTOP-9CG3290 ~
$
```

## 2.2 Example Managed Linux Server

| Component | Details |
|---|---|
| Hostname | ansible-server-01 |
| IP Address | 192.168.253.145 |
| Operating System | Rocky Linux 8.10 |
| SSH User | root |
| Python | Python 3.6.8 |

Another tested host:

```text
Hostname: netbox
IP Address: 192.168.253.143
Operating System: Rocky Linux 8.10
SSH User: root
```

---

# 3. Final Architecture

```text
                    WINDOWS MACHINE
             +---------------------------+
             |                           |
             |          Cygwin           |
             |                           |
             |  Python 3.12              |
             |  Ansible Core 2.16.19     |
             |  OpenSSH                  |
             |  sshpass                  |
             |                           |
             +-------------+-------------+
                           |
                           | SSH
                           | Password Authentication
                           v
             +---------------------------+
             | Rocky Linux 8 / CentOS 8  |
             |                           |
             | SSH Server                |
             | Python 3.6                |
             |                           |
             +---------------------------+
```

The important point is:

```text
Ansible Control Node:
Python 3.12
        +
Ansible Core 2.16.19

Managed Linux Node:
Python 3.6.8
```

Ansible does not require the same Python version on the control node and managed node.

---

# 4. Install Cygwin

Download and install Cygwin on Windows.

During Cygwin package selection, install the required packages.

## Required Packages

Install:

```text
python3
python3-pip
openssh
sshpass
curl
wget
git
vim
vim-common
```

Depending on the Cygwin repository version, package names can vary.

After package installation, close Cygwin and open a new terminal.

---

# 5. Verify Cygwin Dependencies

Run:

```bash
python3 --version
python3 -m pip --version
ssh -V
sshpass -V
```

Expected examples:

```text
Python 3.12.12
```

```text
pip 25.0.1
```

```text
OpenSSH_10.4p1
```

```text
sshpass 1.10
```

Example from the installation:

```text
vigne@DESKTOP-9CG3290 ~
$ sshpass -V
sshpass 1.10
(C) 2006-2011 Lingnu Open Source Consulting Ltd.
(C) 2015-2016, 2021-2022 Shachar Shemesh
This program is free software, and can be distributed under the terms of the GPL
See the COPYING file for more information.

Using "assword" as the default password prompt indicator.
```

---

# 6. Verify Python and pip on Cygwin

Run:

```bash
python3 --version
python3 -m ensurepip --version
```

Example:

```text
vigne@DESKTOP-9CG3290 ~
$ python3 --version
python3 -m ensurepip --version
Python 3.12.12
pip 25.0.1
```

This confirmed that Python 3.12 was installed on the Cygwin Ansible control node.

---

# 7. Initial Ansible Installation

Initially, Ansible was installed with a newer version.

Check:

```bash
ansible --version
```

The initial version was:

```text
ansible [core 2.21.3]
```

Example:

```text
ansible [core 2.21.3]
config file = None
configured module search path = ['/home/vigne/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
ansible python module location = /home/vigne/.local/lib/python3.12/site-packages/ansible
ansible collection location = /home/vigne/.ansible/collections:/usr/share/ansible/collections
executable location = /home/vigne/.local/bin/ansible
python version = 3.12.12
```

The newer Ansible installation itself worked correctly on Cygwin.

However, a compatibility issue occurred later with managed hosts running Python 3.6.

---

# 8. Create Initial Inventory

Create the inventory file:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
EOF
```

Check the file:

```bash
cat ~/inventory.ini
```

Example:

```ini
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
```

Check inventory parsing:

```bash
ansible-inventory -i ~/inventory.ini --graph
```

Example output:

```text
@all:
|--@ungrouped:
|--@linux:
|  |--netbox
```

---

# 9. Initial SSH Key Authentication Attempt

Initially, SSH key authentication was configured.

Ansible attempted to use:

```text
/home/vigne/ANSIBLE/ssh-admin/files/id_rsa
```

The SSH connection failed with:

```text
root@192.168.253.143: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password).
```

Ansible showed:

```text
netbox | UNREACHABLE! => {
    "changed": false,
    "msg": "Task failed: Failed to connect to the host via ssh: root@192.168.253.143: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password).",
    "unreachable": true
}
```

The private key itself was valid.

Its fingerprint was:

```text
4096 SHA256:VK2tuWdtSnQvdMRcbwb5O0l8hj7bY3yKNjajiHgEi40 no comment (RSA)
```

However, the managed server did not accept the key.

The decision was made to stop troubleshooting SSH keys and use SSH password authentication.

---

# 10. Test Manual SSH Password Login

Before configuring Ansible, test normal SSH.

Run:

```bash
ssh root@192.168.253.143
```

Enter the root password.

Example successful login:

```text
==================================================
 Rocky Linux 8.10 Enterprise Golden Image
 UEFI + GPT + Single Disk
==================================================

Activate the web console with: systemctl enable --now cockpit.socket

[root@netbox ~]#
```

This confirmed:

```text
Network connectivity = Working
SSH service = Working
Root login = Working
Password authentication = Working
```

Therefore Ansible could use password authentication.

---

# 11. Install and Verify sshpass

Verify:

```bash
sshpass -V
```

Example:

```text
sshpass 1.10
```

The `sshpass` package is useful for password-based automation, although normal Ansible interactive testing can use:

```bash
--ask-pass
```

---

# 12. Test Ansible Using Password Authentication

Run:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

Ansible prompts:

```text
SSH password:
```

Enter the Linux server root password.

Initially, another SSH-related issue occurred.

---

# 13. SSH ControlMaster Problem on Cygwin

The following error occurred:

```text
mux_client_request_session: read from master failed: Connection reset by peer
Failed to connect to new control master
```

The complete Ansible error looked like:

```text
[ERROR]: Task failed: Failed to connect to the host via ssh:
mux_client_request_session: read from master failed: Connection reset by peer
Failed to connect to new control master
```

This was related to SSH connection multiplexing.

Ansible/OpenSSH attempted to use ControlMaster connections.

For this Cygwin environment, the solution was to disable SSH ControlMaster.

---

# 14. Fix SSH ControlMaster Issue

Create the inventory with the following SSH arguments:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Clear old Ansible SSH control sockets:

```bash
rm -rf ~/.ansible/cp
mkdir -p ~/.ansible/cp
```

Do not use `pkill ssh` if the command does not exist in your Cygwin installation.

The important fix is:

```ini
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

This disables SSH multiplexing.

---

# 15. Post-Quantum SSH Warning

The following warning appeared during SSH connections:

```text
** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
** The server may need to be upgraded.
See https://openssh.com/pq.html
```

This warning was not the cause of the Ansible failure.

The SSH connection could still authenticate and run commands.

The actual problems encountered were:

```text
1. SSH key was not accepted
2. SSH ControlMaster issue in Cygwin
3. Python was missing on the managed host
4. Python version was too old for Ansible Core 2.21
```

For this lab, the post-quantum warning did not prevent Ansible from working.

---

# 16. Managed Host Had No Python

After the SSH problem was fixed, Ansible produced:

```text
The module interpreter '/usr/bin/python3' was not found.
```

Ansible output:

```text
netbox | FAILED! => {
    "changed": false,
    "module_stdout": "/bin/sh: /usr/bin/python3: No such file or directory\r\n",
    "msg": "The module interpreter '/usr/bin/python3' was not found.",
    "rc": 127
}
```

Manual verification:

```bash
ssh root@192.168.253.143
```

Then run:

```bash
which python3
which python
ls -l /usr/bin/python*
```

Output:

```text
/usr/bin/which: no python3 in (/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin)

/usr/bin/which: no python in (/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin)

ls: cannot access '/usr/bin/python*': No such file or directory
```

This confirmed that the managed Rocky Linux server had no Python installed.

---

# 17. Important: What to Do if Managed Host Has No Python

Normal Ansible modules require Python on the managed host.

For example, these normally require Python:

```text
ping
setup
command
yum
dnf
package
copy
template
service
user
```

If Python is missing, use the Ansible `raw` module.

The `raw` module does not require Python.

It sends the command directly through SSH.

---

# 18. Install Python Remotely Using raw Module

For a host without Python, use:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

Example inventory used:

```ini
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Important:

When Python is not installed, do not configure:

```ini
ansible_python_interpreter=/usr/bin/python3
```

yet.

First use `raw` to install Python.

Run:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

---

# 19. Successful Python Installation

The command successfully installed:

```text
python36
python3-pip
```

Example output:

```text
Installing:
 python36     x86_64  3.6.8-39.module+el8.10.0+1910+234ad790.x86_64

Installing dependencies:
 python3-pip  noarch  9.0.3-24.el8.rocky.0.noarch
```

Installation completed with:

```text
Installed:
  python3-pip-9.0.3-24.el8.rocky.0.noarch
  python36-3.6.8-39.module+el8.10.0+1910+234ad790.x86_64

Complete!
```

This confirmed Python was installed on the managed host.

---

# 20. Verify Python on the Managed Host

SSH manually:

```bash
ssh root@192.168.253.145
```

Run:

```bash
python3.6 --version
which python3.6
```

Expected:

```text
Python 3.6.8
/usr/bin/python3.6
```

Check whether `/usr/bin/python3` exists:

```bash
ls -l /usr/bin/python3
```

If it exists and points to Python 3.6, it can be used.

However, the safest inventory configuration is the exact interpreter:

```ini
ansible_python_interpreter=/usr/bin/python3.6
```

---

# 21. Python 3.6 and Ansible Core 2.21 Compatibility Problem

After Python 3.6 was installed, Ansible Core 2.21 was tested.

The command was:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

The result failed with:

```text
Module result deserialization failed: No start of json char found
```

The actual cause was:

```text
File "/root/.ansible/tmp/.../AnsiballZ_ping.py", line 3
    from __future__ import annotations
    ^
SyntaxError: future feature annotations is not defined
```

The managed host was running:

```text
Python 3.6.8
```

The Ansible control node was running:

```text
Ansible Core 2.21.3
```

The newer Ansible-generated module code was not compatible with Python 3.6.

---

# 22. Solution: Use Ansible Core 2.16

To manage older hosts using Python 3.6, use Ansible Core 2.16.

The selected version was:

```text
Ansible Core 2.16.19
```

The installation target was:

```text
ansible-core==2.16.*
```

---

# 23. Virtual Environment Attempt

An attempt was first made to create a Python virtual environment:

```bash
python3 -m venv ~/ansible216
```

It failed:

```text
Error: Command '['/home/vigne/ansible216/bin/python3', '-m', 'ensurepip', '--upgrade', '--default-pip']' returned non-zero exit status 1.
```

Another attempt was made:

```bash
rm -rf ~/ansible216

python3 -m venv --without-pip ~/ansible216
```

Activate it:

```bash
source ~/ansible216/bin/activate
```

Verify:

```bash
which python
python --version
```

Output:

```text
/home/vigne/ansible216/bin/python
Python 3.12.12
```

Then:

```bash
python -m ensurepip --upgrade
```

This failed with:

```text
FileNotFoundError: [Errno 2] No such file or directory:
'/usr/lib/python3.12/ensurepip/_bundled/pip-25.0.1-py3-none-any.whl'
```

The required pip wheel was missing from the Cygwin Python installation.

Therefore, the virtual environment method was not used.

---

# 24. Install Ansible Core 2.16 Directly

Install Ansible Core 2.16:

```bash
python3 -m pip install --user --upgrade "ansible-core==2.16.*"
```

The installation selected:

```text
ansible-core-2.16.19
```

Example result:

```text
Successfully installed ansible-core-2.16.19 resolvelib-1.0.1
```

A dependency warning appeared:

```text
ansible 14.3.0 requires ansible-core~=2.21.3, but you have ansible-core 2.16.19 which is incompatible.
```

The important part is that the `ansible` command should run with Ansible Core 2.16.19.

Verify:

```bash
ansible --version
```

Expected output:

```text
ansible [core 2.16.19]
```

Example:

```text
vigne@DESKTOP-9CG3290 ~
$ ansible --version
ansible [core 2.16.19]
  config file = None
  configured module search path = ['/home/vigne/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/local/lib/python3.12/site-packages/ansible
  ansible collection location = /home/vigne/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/local/bin/ansible
  python version = 3.12.12
  jinja version = 3.1.6
  libyaml = False
```

---

# 25. Final Inventory for Rocky Linux 8 with Python 3.6

After Python 3.6 is installed, create:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Check:

```bash
cat ~/inventory.ini
```

Expected:

```ini
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

---

# 26. Final Ping Test

Run:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Enter the SSH password.

Expected:

```text
ansible-server-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

This confirms the complete setup is working.

---

# 27. Standard Procedure for a New Linux Server

Use these steps whenever adding a new Linux server.

## Step 1: Add the Server to Inventory

If Python status is unknown, start with:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
server01 ansible_host=192.168.253.141

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Do not add `ansible_python_interpreter` yet.

---

## Step 2: Test Manual SSH

Run:

```bash
ssh root@192.168.253.141
```

Enter the password.

Confirm that SSH works.

Exit:

```bash
exit
```

---

## Step 3: Check Whether Python Exists

Use Ansible raw:

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "python3.6 --version || python3 --version || python --version" \
  --ask-pass
```

If Python exists, note the path and version.

---

## Step 4: If Python Does Not Exist, Install It

For Rocky Linux 8:

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "yum install -y python36" \
  --ask-pass
```

For systems using DNF:

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "dnf install -y python3" \
  --ask-pass
```

---

## Step 5: Verify Python

Run:

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "python3.6 --version" \
  --ask-pass
```

Expected:

```text
Python 3.6.8
```

---

## Step 6: Update Inventory

After Python installation:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
server01 ansible_host=192.168.253.141

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

---

## Step 7: Test Ansible

Run:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Expected:

```text
server01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

# 28. Managing Multiple Linux Servers

Example inventory:

```ini
[linux]
server01 ansible_host=192.168.253.141
server02 ansible_host=192.168.253.142
netbox ansible_host=192.168.253.143
server04 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Test all Linux servers:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Test every inventory host:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

---

# 29. Multiple Servers Without Python

If multiple new servers do not have Python installed, use:

```ini
[linux]
server01 ansible_host=192.168.253.141
server02 ansible_host=192.168.253.142
server03 ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Install Python on all servers:

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "yum install -y python36" \
  --ask-pass
```

After installation, update inventory:

```ini
[linux]
server01 ansible_host=192.168.253.141
server02 ansible_host=192.168.253.142
server03 ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Then test:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

---

# 30. Useful Ansible Commands

## Check Ansible Version

```bash
ansible --version
```

Expected:

```text
ansible [core 2.16.19]
```

---

## Check Python on Control Node

```bash
python3 --version
```

---

## Check Inventory

```bash
ansible-inventory -i ~/inventory.ini --graph
```

---

## Ping All Hosts

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

---

## Ping Linux Group

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

---

## Run hostname Command

```bash
ansible linux -i ~/inventory.ini \
  -m command \
  -a "hostname" \
  --ask-pass
```

---

## Check Operating System

```bash
ansible linux -i ~/inventory.ini \
  -m command \
  -a "cat /etc/os-release" \
  --ask-pass
```

---

## Check Python Version

```bash
ansible linux -i ~/inventory.ini \
  -m command \
  -a "python3.6 --version" \
  --ask-pass
```

---

## Gather Ansible Facts

```bash
ansible linux -i ~/inventory.ini \
  -m setup \
  --ask-pass
```

---

## Run a Raw Command

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "uname -a" \
  --ask-pass
```

---

## Install Python on Hosts Without Python

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "yum install -y python36" \
  --ask-pass
```

---

## Verbose Ansible Troubleshooting

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass -vvvv
```

---

# 31. Vim Issue Encountered in Cygwin

Initially, running:

```bash
vim inventory.ini
```

failed with:

```text
Error detected while processing /etc/vimrc:
line   90:
E484: Can't open file /usr/share/vim/syntax/syntax.vim
E1187: Failed to source defaults.vim
```

Running:

```bash
vi inventory.ini
```

also failed.

The system contained:

```bash
/usr/share/vim/vim91/defaults.vim
/usr/share/vim/vim91/syntax/syntax.vim
```

Verification commands:

```bash
ls -l /usr/share/vim
ls -l /usr/share/vim/vim91
ls -l /usr/share/vim/vim91/syntax/syntax.vim
```

The output confirmed:

```text
/usr/share/vim/vim91/defaults.vim
/usr/share/vim/vim91/syntax/syntax.vim
```

However, Vim attempted to load:

```text
/usr/share/vim/syntax/syntax.vim
```

instead of:

```text
/usr/share/vim/vim91/syntax/syntax.vim
```

This was a Vim runtime configuration/package issue.

As a workaround, inventory files were created using `cat` and a heredoc.

Example:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Then verify:

```bash
cat ~/inventory.ini
```

---

# 32. Troubleshooting Summary

## Problem 1: SSH Key Authentication Failed

### Error

```text
Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)
```

### Cause

The SSH public key was not accepted by the managed server.

### Fix

Use password authentication:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

---

## Problem 2: SSH ControlMaster Error

### Error

```text
mux_client_request_session: read from master failed: Connection reset by peer
Failed to connect to new control master
```

### Cause

SSH multiplexing did not work reliably in the Cygwin setup.

### Fix

Add:

```ini
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Clear old sockets:

```bash
rm -rf ~/.ansible/cp
mkdir -p ~/.ansible/cp
```

---

## Problem 3: Python Missing on Managed Host

### Error

```text
The module interpreter '/usr/bin/python3' was not found.
```

### Cause

Python was not installed.

### Fix

Use the raw module:

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "yum install -y python36" \
  --ask-pass
```

---

## Problem 4: Ansible Core 2.21 Failed on Python 3.6

### Error

```text
SyntaxError: future feature annotations is not defined
```

### Cause

The managed host used Python 3.6 and Ansible Core 2.21 module code was incompatible.

### Fix

Install Ansible Core 2.16:

```bash
python3 -m pip install --user --upgrade "ansible-core==2.16.*"
```

Verify:

```bash
ansible --version
```

Expected:

```text
ansible [core 2.16.19]
```

---

## Problem 5: Virtual Environment Failed

### Error

```text
FileNotFoundError:
'/usr/lib/python3.12/ensurepip/_bundled/pip-25.0.1-py3-none-any.whl'
```

### Cause

The required bundled pip wheel was missing from the Cygwin Python installation.

### Fix Used

Do not use the virtual environment.

Install the required Ansible Core version directly:

```bash
python3 -m pip install --user --upgrade "ansible-core==2.16.*"
```

---

## Problem 6: Vim Runtime Error

### Error

```text
E484: Can't open file /usr/share/vim/syntax/syntax.vim
E1187: Failed to source defaults.vim
```

### Cause

Cygwin Vim runtime path/package configuration issue.

### Workaround

Create files using:

```bash
cat > ~/inventory.ini <<'EOF'
...
EOF
```

instead of using Vim until the Vim installation is fixed.

---

# 33. Final Recommended Configuration

## Control Node

```text
Windows
└── Cygwin
    ├── Python 3.12.12
    ├── Ansible Core 2.16.19
    ├── OpenSSH
    ├── sshpass
    └── Git
```

## Managed Node

For Rocky Linux 8/CentOS systems:

```text
Rocky Linux 8 / CentOS
├── SSH enabled
├── SSH password authentication
├── Python 3.6.8
└── Ansible managed remotely
```

## Final Inventory

```ini
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

## Final Test

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Expected:

```text
ansible-server-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

# 34. Complete Quick Setup From Scratch

The following is the recommended quick procedure.

## On Cygwin

Verify Python:

```bash
python3 --version
python3 -m pip --version
```

Verify SSH:

```bash
ssh -V
sshpass -V
```

Install compatible Ansible:

```bash
python3 -m pip install --user --upgrade "ansible-core==2.16.*"
```

Verify:

```bash
ansible --version
```

Expected:

```text
ansible [core 2.16.19]
```

Create initial inventory for a host that may not have Python:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Test manual SSH:

```bash
ssh root@192.168.253.145
```

Exit:

```bash
exit
```

Install Python remotely:

```bash
ansible linux -i ~/inventory.ini \
  -m raw \
  -a "yum install -y python36" \
  --ask-pass
```

Update inventory:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.6
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Test:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Expected:

```text
ansible-server-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

# 35. Final Checklist

```text
[ ] Windows installed
[ ] Cygwin installed
[ ] Python 3 installed on Cygwin
[ ] pip installed
[ ] OpenSSH installed
[ ] sshpass installed
[ ] Ansible Core 2.16 installed
[ ] ansible --version shows 2.16.x
[ ] Manual SSH password login works
[ ] inventory.ini created
[ ] SSH ControlMaster disabled
[ ] Python checked on managed host
[ ] Python installed with raw module if missing
[ ] ansible_python_interpreter configured correctly
[ ] ansible ping returns pong
```

---

# 36. Key Lessons Learned

1. Ansible runs from Cygwin successfully on Windows.

2. The control node and managed node do not need the same Python version.

3. If the managed Linux server does not have Python, use:

```bash
ansible ... -m raw
```

to install Python first.

4. For this environment, Rocky Linux 8 provided Python 3.6.

5. Ansible Core 2.21 was incompatible with the Python 3.6 managed host.

6. Ansible Core 2.16.19 was used for compatibility.

7. SSH password authentication works using:

```bash
--ask-pass
```

8. The Cygwin SSH ControlMaster issue was fixed by adding:

```ini
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

9. The post-quantum SSH warning was not the cause of the Ansible failures.

10. Always test manual SSH first before troubleshooting Ansible.

11. Always check whether Python exists on a new managed server before running normal Ansible modules.

---

# END OF SOP
