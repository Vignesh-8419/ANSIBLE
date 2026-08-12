# SOP: Install and Configure Ansible on Cygwin for Managing CentOS/Rocky Linux Hosts

## 1. Purpose

This SOP explains the complete setup performed to run Ansible from:

- Windows 10
- Cygwin
- Python 3.12
- Password-based SSH authentication

It also documents the problems encountered and their fixes, including:

- Cygwin Ansible installation
- Python virtual environment issue
- Ansible version compatibility
- SSH ControlMaster/multiplexing issue
- Managed host without Python
- CentOS/Rocky Linux Python 3.6 compatibility
- Using the Ansible `raw` module to install Python
- Inventory configuration
- Password authentication using `--ask-pass`
- Vim installation/runtime issue

---

# 2. Environment

## Ansible Control Node

Operating System:

```text
Windows 10
```

Shell environment:

```text
Cygwin
```

Example Cygwin user:

```text
vigne
```

Example home directory:

```text
/home/vigne
```

Python version on Cygwin:

```text
Python 3.12.12
```

Ansible Core version selected for compatibility with Python 3.6 managed hosts:

```text
ansible-core 2.16.19
```

SSH authentication:

```text
Password authentication
```

---

# 3. Example Managed Hosts

Example NetBox server:

```text
Hostname: netbox
IP Address: 192.168.253.143
Operating System: Rocky Linux 8.10
```

Example Ansible managed server:

```text
Hostname: ansible-server-01
IP Address: 192.168.253.145
Operating System: Rocky Linux 8.10 / CentOS/Rocky Linux
```

Example SSH user:

```text
root
```

---

# 4. Important Ansible Architecture

Ansible consists of two main parts.

## 4.1 Control Node

The machine where Ansible runs.

In this setup:

```text
Windows
   |
   +-- Cygwin
          |
          +-- Python 3.12
          |
          +-- Ansible Core 2.16.19
```

The Cygwin machine is the Ansible Control Node.

Python is required on the Control Node.

## 4.2 Managed Node

The Linux server controlled by Ansible.

Examples:

```text
192.168.253.143
192.168.253.145
```

The managed node does NOT need Ansible installed.

Normally, however, it needs Python for standard Ansible modules such as:

```text
ping
setup
command
shell
yum
dnf
copy
template
service
user
file
```

If Python is not installed on the managed host, use the `raw` module first.

The `raw` module does not require Python on the managed host.

Example:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

---

# 5. Install Cygwin

Install Cygwin on Windows.

During Cygwin package selection, install the required packages.

Search for and install:

```text
python3
python3-pip
python3-devel
python3-setuptools
openssh
openssh-clients
sshpass
vim
python312-cryptography
python312-jinja2
python312-PyYAML
python3-wheel
```

Recommended additional packages:

```text
curl
wget
git
nano
tar
gzip
```

Then verify the dependencies:

```bash
python3 -c "import cryptography; print(cryptography.__version__)"
python3 -c "import jinja2; print(jinja2.__version__)"
python3 -c "import yaml; print(yaml.__version__)"
```

Since PyYAML is a pure Python dependency, install it with pip:

```bash
python3 -m pip install --user PyYAML
```

Then verify:

```bash
python3 -c "import yaml; print(yaml.__version__)"
```

If successful, install the remaining dependency:

```bash
python3 -m pip install --user "resolvelib>=0.5.3,<1.1.0"
```

Then install Ansible Core 2.16 without reinstalling/building cryptography:

After installation, open Cygwin Terminal.

Check the Python version:

```bash
python3 --version
```

Expected example output:

```text
Python 3.12.12
```

Check pip:

```bash
python3 -m pip --version
```

Expected example output:

```text
pip 25.0.1
```

or another installed pip version.

---

# 6. Install Ansible on Cygwin

First check whether Ansible is already installed:

```bash
ansible --version
```

Also check pip packages:

```bash
python3 -m pip show ansible
python3 -m pip show ansible-core
```

Initially, the system had a newer Ansible version:

```text
ansible-core 2.21.3
```

This caused a compatibility problem with managed hosts using Python 3.6.

The solution was to use:

```text
ansible-core 2.16.x
```

Specifically:

```text
ansible-core 2.16.19
```

Install or change to Ansible Core 2.16:

```bash
python3 -m pip install --upgrade "ansible-core==2.16.*"
```

Check the version:

```bash
ansible --version
```

Expected result:

```text
ansible [core 2.16.19]
```

Example:

```text
ansible [core 2.16.19]
  config file = None
  configured module search path = ['/home/vigne/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/local/lib/python3.12/site-packages/ansible
  ansible collection location = /home/vigne/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/local/bin/ansible
  python version = 3.12.12
```

Verify the installed Ansible Core package:

```bash
python3 -m pip show ansible-core
```

Expected version:

```text
Version: 2.16.19
```

---

# 7. Important Note About Ansible Package Conflicts

During installation, the following type of message may appear:

```text
ERROR: pip's dependency resolver does not currently take into account all the packages that are installed.

ansible 14.3.0 requires ansible-core~=2.21.3,
but you have ansible-core 2.16.19 which is incompatible.
```

This happened because the full `ansible` package was installed and expected:

```text
ansible-core 2.21.3
```

while the required compatibility version was:

```text
ansible-core 2.16.19
```

For this environment, the important executable is:

```text
ansible-core 2.16.19
```

Verify using:

```bash
ansible --version
```

Expected:

```text
ansible [core 2.16.19]
```

If required, remove the conflicting full Ansible package:

```bash
python3 -m pip uninstall ansible
```

Then ensure Ansible Core 2.16 is installed:

```bash
python3 -m pip install --upgrade "ansible-core==2.16.*"
```

Verify:

```bash
ansible --version
```

---

# 8. Virtual Environment Issue Encountered

An attempt was made to create a virtual environment:

```bash
python3 -m venv ~/ansible216
```

The following error occurred:

```text
Error: Command '['/home/vigne/ansible216/bin/python3',
'-m', 'ensurepip', '--upgrade', '--default-pip']'
returned non-zero exit status 1.
```

Python itself was verified:

```bash
python3 --version
```

Result:

```text
Python 3.12.12
```

Ensurepip was also checked:

```bash
python3 -m ensurepip --version
```

Result:

```text
pip 25.0.1
```

A virtual environment was then created without pip:

```bash
rm -rf ~/ansible216

python3 -m venv --without-pip ~/ansible216
```

Activate it:

```bash
source ~/ansible216/bin/activate
```

Check Python:

```bash
which python
python --version
```

Example:

```text
/home/vigne/ansible216/bin/python
Python 3.12.12
```

Another ensurepip error occurred:

```text
FileNotFoundError: [Errno 2] No such file or directory:
'/usr/lib/python3.12/ensurepip/_bundled/pip-25.0.1-py3-none-any.whl'
```

Therefore, the final working approach was to install and use Ansible directly from the available Python/pip environment instead of depending on this broken virtual environment.

Final verification:

```bash
ansible --version
python3 -m pip show ansible-core
```

Expected:

```text
ansible [core 2.16.19]
```

---

# 9. Verify SSH Connectivity Before Using Ansible

Before troubleshooting Ansible, first test normal SSH.

Example:

```bash
ssh root@192.168.253.143
```

Enter the password when prompted.

Example:

```text
root@192.168.253.143's password:
```

If login is successful, SSH connectivity is working.

Exit:

```bash
exit
```

Example:

```text
Connection to 192.168.253.143 closed.
```

If normal SSH does not work, fix SSH before troubleshooting Ansible.

---

# 10. Password Authentication with Ansible

The goal of this setup is password-based authentication.

Do NOT use an SSH private key in the inventory.

Use:

```bash
--ask-pass
```

Example:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

Ansible will prompt:

```text
SSH password:
```

Enter the root password for the managed server.

For multiple hosts with the same SSH password, the password can be entered once for the command.

---

# 11. Install and Verify sshpass

Ansible may use `sshpass` for password-based automation.

Check whether it is installed:

```bash
sshpass -V
```

Example output:

```text
sshpass 1.10
(C) 2006-2011 Lingnu Open Source Consulting Ltd.
(C) 2015-2016, 2021-2022 Shachar Shemesh
```

If `sshpass` is not installed, install it through the Cygwin installer.

Package:

```text
sshpass
```

Then verify again:

```bash
sshpass -V
```

---

# 12. Create the Ansible Inventory

Create the inventory file:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Check the file:

```bash
cat ~/inventory.ini
```

Expected:

```ini
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Another example:

```ini
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

For multiple servers:

```ini
[linux]
netbox ansible_host=192.168.253.143
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

---

# 13. Verify Inventory

Run:

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

For multiple hosts:

```text
@all:
|--@ungrouped:
|--@linux:
|  |--netbox
|  |--ansible-server-01
```

---

# 14. SSH ControlMaster Issue Encountered on Cygwin

Initially, Ansible was run using:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

The following error occurred:

```text
mux_client_request_session: read from master failed: Connection reset by peer
Failed to connect to new control master
```

The complete connection issue included:

```text
** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
mux_client_request_session: read from master failed: Connection reset by peer
Failed to connect to new control master
```

The post-quantum warning was NOT the actual authentication problem.

The actual issue was SSH multiplexing / ControlMaster behavior in the Cygwin environment.

The fix was to disable SSH multiplexing.

Use this in the inventory:

```ini
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Remove old Ansible SSH control sockets:

```bash
rm -rf ~/.ansible/cp
```

Create the directory again:

```bash
mkdir -p ~/.ansible/cp
```

The final inventory should be:

```ini
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Test again:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

---

# 15. Post-Quantum SSH Warning

The following warning appeared:

```text
** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
** The server may need to be upgraded.
```

This warning is informational.

It was displayed because:

```text
Cygwin OpenSSH client is newer
```

and the managed server is using an older OpenSSH version.

For example:

```text
Client: OpenSSH_10.4
Server: OpenSSH_8.0
```

This warning was NOT the reason Ansible failed.

The actual issues encountered were:

```text
SSH ControlMaster/multiplexing
```

and later:

```text
Missing Python on the managed host
```

and:

```text
Python 3.6 incompatibility with newer Ansible Core
```

Therefore, do not treat the post-quantum warning as the main Ansible error.

---

# 16. Managed Host Without Python

When Ansible was first tested, the managed server did not have Python installed.

The inventory originally contained:

```ini
ansible_python_interpreter=/usr/bin/python3
```

Ansible returned:

```text
The module interpreter '/usr/bin/python3' was not found.
```

The managed host was checked manually:

```bash
ssh root@192.168.253.143
```

Then:

```bash
which python3
```

Output:

```text
/usr/bin/which: no python3 in (/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin)
```

Check Python:

```bash
which python
```

Output:

```text
/usr/bin/which: no python in (/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin)
```

Check Python binaries:

```bash
ls -l /usr/bin/python*
```

Output:

```text
ls: cannot access '/usr/bin/python*': No such file or directory
```

This confirmed that the managed host had no Python.

---

# 17. Important Rule: Do Not Use Normal Ansible Modules Before Python Exists

The following command will fail if Python is missing:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

The reason is that the `ping` module requires Python on the managed host.

Instead, use the `raw` module.

The `raw` module sends commands directly over SSH and does not require Python.

---

# 18. Install Python on a Managed Rocky Linux 8 / CentOS 8 Host

First, use an inventory without forcing a Python interpreter.

Example:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Check it:

```bash
cat ~/inventory.ini
```

Expected:

```ini
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Install Python using the `raw` module:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

Example successful output:

```text
ansible-server-01 | CHANGED | rc=0 >>
```

The installation installs packages such as:

```text
python36
python3-pip
```

Example:

```text
Installed:
python3-pip
python36
```

After installation, Python becomes available on the managed server.

---

# 19. Verify Python on the Managed Host

Connect manually:

```bash
ssh root@192.168.253.145
```

Check Python:

```bash
python3 --version
```

For Python 3.6:

```text
Python 3.6.8
```

Also check the actual interpreter path:

```bash
which python3
```

Possible result:

```text
/usr/bin/python3
```

Check Python 3.6:

```bash
python3.6 --version
```

Example:

```text
Python 3.6.8
```

Check available Python binaries:

```bash
ls -l /usr/bin/python*
```

---

# 20. Python 3.6 Compatibility Issue

After Python 3.6 was installed, Ansible Core 2.21 was initially used.

The Ansible ping command failed with:

```text
Module result deserialization failed: No start of json char found
```

The important error was:

```text
SyntaxError: future feature annotations is not defined
```

Example:

```text
File "/root/.ansible/tmp/.../AnsiballZ_ping.py", line 3
    from __future__ import annotations
    ^
SyntaxError: future feature annotations is not defined
```

This happened because the Ansible version on the Cygwin Control Node was too new for the Python 3.6 interpreter on the managed host.

The managed host had:

```text
Python 3.6.8
```

The Control Node had:

```text
ansible-core 2.21.3
```

The solution was to use:

```text
ansible-core 2.16.19
```

---

# 21. Install Ansible Core 2.16 for Python 3.6 Managed Hosts

Check the current version:

```bash
ansible --version
```

Install the compatible version:

```bash
python3 -m pip install --upgrade "ansible-core==2.16.*"
```

Verify:

```bash
ansible --version
```

Expected:

```text
ansible [core 2.16.19]
```

Also verify:

```bash
python3 -m pip show ansible-core
```

Expected:

```text
Name: ansible-core
Version: 2.16.19
```

This version was used because the managed CentOS/Rocky Linux host was running Python 3.6.

---

# 22. Configure the Python Interpreter in Inventory

After Python has been installed and verified on the managed host, specify the correct interpreter if required.

For Python 3.9:

```ini
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.9
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

This configuration successfully produced:

```text
netbox | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

For Python 3.6, use the actual path found on the server.

For example:

```ini
ansible_python_interpreter=/usr/bin/python3
```

or:

```ini
ansible_python_interpreter=/usr/bin/python3.6
```

Verify the correct path first:

```bash
ssh root@192.168.253.145
```

Then:

```bash
which python3
which python3.6
```

Use the path that actually exists.

---

# 23. Final Inventory Example for a Python 3.6 Host

If the managed host uses Python 3.6:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Check:

```bash
cat ~/inventory.ini
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

# 24. Final Inventory Example for a Python 3.9 Host

If the managed host uses Python 3.9:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.9
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Test:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

Expected:

```text
netbox | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

# 25. Complete Workflow for a New Managed Server Without Python

Use the following procedure whenever adding a new CentOS/Rocky Linux server.

## Step 1: Add the Server to Inventory Without Python Interpreter

Create:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
new-server ansible_host=192.168.253.150

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Do NOT add:

```ini
ansible_python_interpreter=/usr/bin/python3
```

yet because Python may not exist.

## Step 2: Verify Manual SSH

```bash
ssh root@192.168.253.150
```

Enter the password.

Exit:

```bash
exit
```

## Step 3: Install Python Using raw

For Rocky Linux 8 / CentOS 8:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

If the host uses DNF:

```bash
ansible linux -i ~/inventory.ini -m raw -a "dnf install -y python3" --ask-pass
```

## Step 4: Verify Python

Connect:

```bash
ssh root@192.168.253.150
```

Check:

```bash
which python3
python3 --version
```

Also check:

```bash
which python3.6
which python3.9
```

Exit:

```bash
exit
```

## Step 5: Add the Correct Python Interpreter

For example:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
new-server ansible_host=192.168.253.150

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

## Step 6: Test Ansible

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Expected:

```text
new-server | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

# 26. Complete Workflow for Multiple Hosts

Example inventory:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
netbox ansible_host=192.168.253.143
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Check inventory:

```bash
ansible-inventory -i ~/inventory.ini --graph
```

Install Python on hosts that do not have it:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

After Python installation, verify the interpreter path on each host.

Then update the inventory if all hosts use the same Python path:

```ini
[linux]
netbox ansible_host=192.168.253.143
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Test:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

---

# 27. What Happens if There Is No Python on the Inventory Server?

Ansible inventory entries do not need Python themselves.

An inventory file is simply configuration on the Control Node.

Example:

```ini
[linux]
server1 ansible_host=192.168.253.150
```

The important Python requirement is normally on the Ansible Control Node and on the managed host.

The Control Node in this setup has:

```text
Python 3.12.12
```

If the managed host has no Python:

Normal modules fail:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Use `raw`:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

Then use normal modules after Python installation.

---

# 28. Common Error: Python Interpreter Not Found

Error:

```text
The module interpreter '/usr/bin/python3' was not found.
```

Cause:

The inventory contains:

```ini
ansible_python_interpreter=/usr/bin/python3
```

but the managed host does not have that file.

Fix:

Remove the interpreter configuration temporarily:

```ini
[linux:vars]
ansible_user=root
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Install Python using raw:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

Verify:

```bash
ssh root@SERVER_IP "which python3 && python3 --version"
```

Then add the correct interpreter path.

---

# 29. Common Error: SyntaxError future feature annotations is not defined

Error:

```text
SyntaxError: future feature annotations is not defined
```

Cause:

A newer Ansible Core version was being used against a Python 3.6 managed host.

Fix:

Install Ansible Core 2.16:

```bash
python3 -m pip install --upgrade "ansible-core==2.16.*"
```

Verify:

```bash
ansible --version
```

Expected:

```text
ansible [core 2.16.19]
```

Then test again:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

---

# 30. Common Error: Failed to Connect to New Control Master

Error:

```text
mux_client_request_session: read from master failed: Connection reset by peer
Failed to connect to new control master
```

Cause:

SSH multiplexing / ControlMaster issue in Cygwin.

Fix the inventory:

```ini
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Remove old sockets:

```bash
rm -rf ~/.ansible/cp
```

Create the directory:

```bash
mkdir -p ~/.ansible/cp
```

Retry:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

---

# 31. Common Error: Permission Denied

Error:

```text
Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)
```

In this SOP, the chosen solution is password authentication.

Do not configure a private key.

Use:

```bash
ansible all -i ~/inventory.ini -m ping --ask-pass
```

Verify normal SSH first:

```bash
ssh root@SERVER_IP
```

If SSH password login works, Ansible can use the same password with:

```bash
--ask-pass
```

---

# 32. Common Error: vim command not found

Initially:

```bash
vim inventory.ini
```

returned:

```text
-bash: vim: command not found
```

Install Vim from the Cygwin setup program.

Package:

```text
vim
```

After installation, verify:

```bash
vim --version
```

---

# 33. Common Vim Runtime Error Encountered

After Vim installation, the following error occurred:

```text
Error detected while processing /etc/vimrc:
line 90:
E484: Can't open file /usr/share/vim/syntax/syntax.vim
E1187: Failed to source defaults.vim
```

The following path did not exist:

```bash
ls -l /usr/share/vim/syntax/syntax.vim
```

Output:

```text
ls: cannot access '/usr/share/vim/syntax/syntax.vim': No such file or directory
```

However, the correct Vim runtime directory existed:

```bash
ls -l /usr/share/vim/vim91
```

The syntax file existed at:

```bash
ls -l /usr/share/vim/vim91/syntax/syntax.vim
```

The output confirmed:

```text
/usr/share/vim/vim91/syntax/syntax.vim
```

Also:

```bash
find /usr/share/vim -name defaults.vim
```

returned:

```text
/usr/share/vim/vim91/defaults.vim
```

This showed that Vim runtime files were installed under:

```text
/usr/share/vim/vim91/
```

instead of:

```text
/usr/share/vim/
```

Check Vim environment:

```bash
echo "VIM=$VIM"
echo "VIMRUNTIME=$VIMRUNTIME"
```

Check Vim version:

```bash
vim --clean --version | head
```

Example:

```text
VIM - Vi IMproved 9.0
```

If the runtime path configuration is broken, reinstall the Vim package from the Cygwin installer so the Vim runtime files and configuration are correctly installed.

---

# 34. Simple Inventory Editing Without Vim

If Vim is not working, create or replace the inventory using:

```bash
cat > ~/inventory.ini <<'EOF'
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.9
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
EOF
```

Check:

```bash
cat ~/inventory.ini
```

This method avoids requiring an editor.

---

# 35. Final Recommended Setup

## Control Node

```text
Windows 10
Cygwin
Python 3.12
Ansible Core 2.16.19
sshpass installed
Password-based SSH authentication
```

Verify:

```bash
python3 --version
```

```bash
ansible --version
```

```bash
sshpass -V
```

Recommended Ansible result:

```text
ansible [core 2.16.19]
```

## Managed Rocky/CentOS 8 Host

For hosts using Python 3.6:

```text
python36
Python 3.6.8
```

Use Ansible Core:

```text
2.16.19
```

Do not use a newer Ansible Core version if it causes Python 3.6 module compatibility errors.

---

# 36. Final Working Inventory Example

For a managed host using Python 3.9:

```ini
[linux]
netbox ansible_host=192.168.253.143

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.9
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

For a managed host using Python 3.6:

```ini
[linux]
ansible-server-01 ansible_host=192.168.253.145

[linux:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Always verify the actual Python path on the managed server before setting:

```ini
ansible_python_interpreter=
```

---

# 37. Final Ansible Test

Run:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Enter:

```text
SSH password:
```

Expected result:

```text
HOSTNAME | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

Example:

```text
netbox | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

or:

```text
ansible-server-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

# 38. Quick Commands Reference

Check Python on Cygwin:

```bash
python3 --version
```

Check pip:

```bash
python3 -m pip --version
```

Install compatible Ansible Core:

```bash
python3 -m pip install --upgrade "ansible-core==2.16.*"
```

Check Ansible:

```bash
ansible --version
```

Check sshpass:

```bash
sshpass -V
```

Check inventory:

```bash
cat ~/inventory.ini
```

Check inventory graph:

```bash
ansible-inventory -i ~/inventory.ini --graph
```

Test normal SSH:

```bash
ssh root@SERVER_IP
```

Test Ansible:

```bash
ansible linux -i ~/inventory.ini -m ping --ask-pass
```

Install Python on a host without Python:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

For DNF-based installation:

```bash
ansible linux -i ~/inventory.ini -m raw -a "dnf install -y python3" --ask-pass
```

Check Python on managed host:

```bash
ssh root@SERVER_IP "which python3 && python3 --version"
```

Remove old Ansible SSH control sockets:

```bash
rm -rf ~/.ansible/cp
mkdir -p ~/.ansible/cp
```

---

# 39. Final Troubleshooting Decision Flow

## Problem: Cannot SSH manually

Test:

```bash
ssh root@SERVER_IP
```

Fix SSH/network/password/firewall first.

Do not troubleshoot Ansible until manual SSH works.

---

## Problem: Ansible says Python is not found

Use:

```bash
ansible linux -i ~/inventory.ini -m raw -a "yum install -y python36" --ask-pass
```

Then verify Python.

---

## Problem: Ansible says `/usr/bin/python3` was not found

Remove the invalid interpreter path from inventory.

Install Python with `raw`.

Find the real path:

```bash
which python3
```

Add that path to:

```ini
ansible_python_interpreter=
```

---

## Problem: `SyntaxError: future feature annotations is not defined`

Managed host is likely using Python 3.6 with an incompatible newer Ansible Core.

Use:

```bash
python3 -m pip install --upgrade "ansible-core==2.16.*"
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

## Problem: `Failed to connect to new control master`

Disable ControlMaster in the inventory:

```ini
ansible_ssh_common_args='-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no'
```

Then:

```bash
rm -rf ~/.ansible/cp
mkdir -p ~/.ansible/cp
```

Retry the Ansible command.

---

## Problem: Post-quantum SSH warning appears

Example:

```text
** WARNING: connection is not using a post-quantum key exchange algorithm.
```

This is informational and was not the cause of the Ansible failures encountered in this setup.

Continue troubleshooting the actual error below the warning.

```bash
git clone https://github.com/vignesh-8419/ANSIBLE.git
```

If you already have an ANSIBLE repository folder:

This downloads only the changes that are missing locally—for example, new files or modified files—not a completely separate copy of the repository.

```bash
cd ~/ANSIBLE
git status
git pull origin main
```

Install the required collection on Cygwin:

```bash
ansible-galaxy collection install community.general
ansible-galaxy collection list | grep community.general
ansible-galaxy collection install ansible.posix
ansible-galaxy collection list | grep ansible.posix
ansible-galaxy collection install theforeman.foreman
ansible-galaxy collection install community.vmware
ansible-galaxy collection install netbox.netbox
```

All at once

```bash
ansible-galaxy collection install \
  ansible.posix \
  community.general \
  community.vmware \
  theforeman.foreman \
  netbox.netbox
```

Run against the linux group

```bash
ansible-playbook -i ~/inventory.ini ssh-admin/create_admin.yml -e "target_hosts=linux" --ask-pass
```

---

# 40. Final SOP Summary

The final working approach is:

```text
1. Install Cygwin on Windows.

2. Install Python 3 and pip in Cygwin.

3. Install sshpass.

4. Install Ansible Core 2.16.19.

5. Use password authentication with --ask-pass.

6. Disable SSH ControlMaster/ControlPath in the inventory for the Cygwin environment.

7. Add Linux servers to inventory.

8. If a managed server has no Python, do not run ping first.

9. Use the raw module to install Python.

10. Verify the Python version and interpreter path.

11. Configure ansible_python_interpreter only after confirming the path exists.

12. For CentOS/Rocky Linux hosts using Python 3.6, use Ansible Core 2.16.19.

13. Run ansible ping with --ask-pass.

14. Successful result should be:
    "ping": "pong"
```

# End of SOP
