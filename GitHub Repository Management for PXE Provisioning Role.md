# GitHub Repository Management for PXE Provisioning Role

## Overview

This document provides the standard operating procedure (SOP) for downloading Ansible playbooks, cloning the GitHub repository, managing Git configuration, creating PXE provisioning role structures, committing changes, and pushing updates to GitHub.

This workflow is used to maintain the centralized automation repository for:

* PXE Provisioning
* AWX Automation
* VMware Automation
* NetBox Integration
* Rocky Linux Deployment
* CentOS Deployment

---

# Repository Information

| Parameter        | Value                                       |
| ---------------- | ------------------------------------------- |
| Git Repository   | https://github.com/Vignesh-8419/ANSIBLE.git |
| Branch           | main                                        |
| Repository Owner | Vignesh-8419                                |
| Repository Type  | Infrastructure Automation                   |

---

# Step 1 - Download Required Playbook

Download the latest version of the static IP configuration playbook.

```bash
wget https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/modified_staticip.yml
```

## Verification

```bash
ls -lh modified_staticip.yml
```

Expected Output:

```text
-rw-r--r-- 1 root root xxxx modified_staticip.yml
```

---

# Step 2 - Clone GitHub Repository

Clone the automation repository locally.

```bash
git clone https://github.com/Vignesh-8419/ANSIBLE.git
```

---

# Step 3 - Change Directory

Navigate to the repository.

```bash
cd ANSIBLE
```

---

# Step 4 - Configure Git Remote

Ensure the repository points to the correct GitHub URL.

```bash
git remote set-url origin https://github.com/Vignesh-8419/ANSIBLE.git
```

## Verify Remote

```bash
git remote -v
```

Expected Output:

```text
origin  https://github.com/Vignesh-8419/ANSIBLE.git (fetch)
origin  https://github.com/Vignesh-8419/ANSIBLE.git (push)
```

---

# Step 5 - Configure Git Credential Storage

Enable persistent Git authentication.

```bash
git config --global credential.helper store
```

## Verify Configuration

```bash
git config --global --get credential.helper
```

Expected Output:

```text
store
```

---

# Step 6 - Initial Push (Optional)

If local commits already exist:

```bash
git push origin main
```

---

# Step 7 - Create PXE Provisioning Role Structure

Create the standard Ansible role directory structure.

```bash
mkdir -p roles/pxe_provision/{tasks,templates,defaults}
```

---

# Directory Structure

```text
roles/
└── pxe_provision/
    ├── tasks/
    ├── templates/
    └── defaults/
```

---

# Step 8 - Add Role Files to Git

Add the PXE role directory.

```bash
git add roles/
```

---

# Step 9 - Add All Repository Changes

Stage all modifications.

```bash
git add -A
```

---

# Verify Staged Files

```bash
git status
```

Example:

```text
Changes to be committed:
  new file: roles/pxe_provision/tasks/main.yml
  new file: roles/pxe_provision/templates/grub-rocky8.j2
  modified: playbooks/os_install.yml
```

---

# Step 10 - Commit Changes

## Option 1 - Save Edited PXE Provisioning Role

```bash
git commit -m "Save edited PXE provisioning role and configs"
```

---

## Option 2 - Initial PXE Role Creation

```bash
git commit -m "Add PXE provisioning role with templates"
```

---

# Step 11 - Push Changes to GitHub

Push the committed changes.

```bash
git push origin main
```

---

# Complete Command Sequence

The following sequence performs the entire workflow:

```bash
wget https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/modified_staticip.yml

git clone https://github.com/Vignesh-8419/ANSIBLE.git

cd ANSIBLE

git remote set-url origin https://github.com/Vignesh-8419/ANSIBLE.git

git config --global credential.helper store

mkdir -p roles/pxe_provision/{tasks,templates,defaults}

git add roles/

git add -A

git commit -m "Save edited PXE provisioning role and configs"

git push origin main
```

---

# Validation Commands

## Check Current Branch

```bash
git branch
```

Expected:

```text
* main
```

---

## Check Repository Status

```bash
git status
```

Expected:

```text
On branch main
nothing to commit, working tree clean
```

---

## View Commit History

```bash
git log --oneline -5
```

Example:

```text
a1b2c3d Save edited PXE provisioning role and configs
e4f5g6h Add PXE provisioning role with templates
```

---

## Verify Remote Repository

```bash
git remote -v
```

---

## Verify Latest Push

```bash
git ls-remote origin main
```

---

# Troubleshooting

## Authentication Failure

Error:

```text
remote: Invalid username or password
```

Resolution:

Use a GitHub Personal Access Token (PAT).

```bash
git config --global credential.helper store
```

Then perform:

```bash
git push origin main
```

---

## Repository Already Exists

Error:

```text
fatal: destination path 'ANSIBLE' already exists
```

Resolution:

```bash
rm -rf ANSIBLE

git clone https://github.com/Vignesh-8419/ANSIBLE.git
```

---

## Nothing to Commit

Error:

```text
nothing to commit, working tree clean
```

Resolution:

Verify files were modified before committing.

```bash
git status
```

---

# Summary

This procedure provides a repeatable workflow for:

* Downloading automation playbooks
* Cloning the ANSIBLE repository
* Managing Git remotes
* Creating PXE provisioning role structures
* Tracking infrastructure-as-code changes
* Committing updates
* Publishing changes to GitHub

This ensures all PXE provisioning and automation assets remain version controlled and centrally managed.
