# AWX 2.7.2 Installation on Kubernetes

![AWX](https://img.shields.io/badge/AWX-2.7.2-red)
![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.30.x-blue)
![Flannel](https://img.shields.io/badge/CNI-Flannel-green)
![Storage](https://img.shields.io/badge/Storage-LocalPath-orange)

---

# Overview

This SOP describes the deployment of AWX 2.7.2 on Kubernetes using:

* Kubernetes v1.30.x
* Flannel CNI
* Local-Path Storage Provisioner
* AWX Operator v2.7.2
* NodePort Service Exposure

---

# Important Notes

> [!WARNING]
> This deployment is intended for LAB / NON-PRODUCTION environments only.

### Lab Assumptions

* Firewall disabled
* NodePort access enabled
* Flannel networking
* Local-path storage
* Single-node or small cluster deployment
* No ingress controller required

---

# Architecture

```text
+----------------------+
|     Kubernetes       |
|      Cluster         |
+----------+-----------+
           |
           v
+----------------------+
|      Flannel CNI     |
+----------+-----------+
           |
           v
+----------------------+
| Local Path Storage   |
+----------+-----------+
           |
           v
+----------------------+
|   AWX Operator 2.7.2 |
+----------+-----------+
           |
           v
+----------------------+
|      AWX Instance    |
|     (NodePort)       |
+----------------------+
```

---

# Prerequisites

| Component         | Version            |
| ----------------- | ------------------ |
| Kubernetes        | v1.30.x            |
| Container Runtime | containerd         |
| OS                | Rocky Linux / RHEL |
| Git               | Installed          |
| Internet Access   | Required           |
| Root Access       | Required           |

---

# Section 1 – Base System Preparation

---

## Step 1 – Disable Firewall

### Purpose

Remove firewall restrictions during lab deployment.

### Commands

```bash
systemctl stop firewalld
systemctl disable firewalld
```

---

## Step 2 – Enable Required Kernel Networking

### Purpose

Enable packet forwarding required by Kubernetes.

### Commands

```bash
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.ipv4.ip_forward=1
```

### Verification

```bash
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward
```

Expected:

```text
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
```

---

## Step 3 – Restart Services

### Commands

```bash
systemctl restart containerd
systemctl restart kubelet
```

---

## Step 4 – Flush IPTables

### Commands

```bash
iptables -F
systemctl restart kubelet
```

---

# Section 2 – Install Flannel CNI

---

## Purpose

Deploy Flannel networking for pod communication.

### Install

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Verification

```bash
kubectl get pods -n kube-system | grep flannel
```

Expected:

```text
kube-flannel-ds-xxxxx   Running
```

---

# Section 3 – Install Local Path Storage

---

## Purpose

Deploy Local Path Provisioner and configure as default StorageClass.

### Install

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
```

---

## Restart Provisioner

```bash
kubectl delete pod -n local-path-storage \
-l app=local-path-provisioner
```

---

## Monitor Logs

```bash
kubectl logs -n local-path-storage \
-l app=local-path-provisioner -f
```

---

## Configure Default StorageClass

```bash
kubectl patch storageclass local-path \
-p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---

## Verification

```bash
kubectl get storageclass
```

Expected:

```text
local-path (default)
```

---

# Section 4 – Install AWX Operator v2.7.2

---

## Create Namespace

```bash
kubectl create namespace awx
```

---

## Install Git

```bash
yum install git -y
```

---

## Clone Repository

```bash
cd ~

git clone https://github.com/ansible/awx-operator.git

cd awx-operator
```

---

## Checkout Version

```bash
git checkout tag/2.7.2
```

---

## Set Version Variable

```bash
export VERSION=2.7.2
```

---

## Deploy Operator

```bash
make deploy
```

---

## Create Kustomization

```bash
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - github.com/ansible/awx-operator/config/default?ref=2.7.2

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.7.2

namespace: awx
EOF
```

---

## Apply Configuration

```bash
kubectl apply -k .
```

---

## Set Namespace Context

```bash
kubectl config set-context \
--current \
--namespace=awx
```

---

# Section 5 – Deploy AWX Instance

---

## Create Admin Password Secret

```bash
kubectl create secret generic awx-admin-password \
--from-literal=password='AdminPassword123' \
-n awx
```

---

## Create AWX Custom Resource

```bash
cat <<EOF > awx-demo.yml
apiVersion: awx.ansible.com/v1beta1
kind: AWX

metadata:
  name: awx-demo

spec:
  service_type: nodeport

  web_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 4Gi

  task_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 4Gi
EOF
```

---

## Create AWX Kustomization

```bash
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - github.com/ansible/awx-operator/config/default?ref=2.7.2
  - awx-demo.yml

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.7.2

namespace: awx
EOF
```

---

## Deploy AWX

```bash
kubectl apply -k .
```

---

# Section 6 – Monitor Installation

---

## Operator Logs

```bash
kubectl logs -f deployment/awx-operator-controller-manager \
-c awx-manager
```

---

## Watch Pods

```bash
kubectl get pods -n awx -w
```

Expected:

```text
awx-demo-postgres-13-0     1/1 Running
awx-demo-task              4/4 Running
awx-demo-web               3/3 Running
```

---

# Section 7 – Access AWX

---

## Get NodePort

```bash
kubectl get svc awx-demo-service -n awx
```

Example:

```text
NAME               TYPE       PORT(S)
awx-demo-service   NodePort   80:32080/TCP
```

---

## Retrieve Admin Password

```bash
kubectl get secret awx-demo-admin-password \
-n awx \
-o jsonpath="{.data.password}" | base64 --decode ; echo
```

---

## Retrieve Admin Username

```bash
kubectl get secret awx-demo-admin-password \
-n awx \
-o jsonpath="{.data.username}" | base64 --decode ; echo
```

---

## Login

```text
URL:
http://<NODE-IP>:<NODEPORT>

Username:
admin

Password:
<Retrieved Password>
```

---

# Section 8 – Troubleshooting

---

## AWX Web Logs

```bash
kubectl logs -f <awx-web-pod> \
-n awx \
-c awx-demo-web
```

---

## AWX Task Logs

```bash
kubectl logs -f <awx-task-pod> \
-n awx \
-c awx-task
```

---

## DNS Test

```bash
kubectl run busybox \
--image=busybox:1.28 \
-n awx \
--rm -it \
--restart=Never -- \
nslookup awx-demo-postgres-13
```

---

## CoreDNS Status

```bash
kubectl get pods -n kube-system \
-l k8s-app=kube-dns
```

```bash
kubectl logs -n kube-system \
-l k8s-app=kube-dns
```

---

## Restart CoreDNS

```bash
kubectl rollout restart deployment coredns \
-n kube-system
```

---

## Check Networking

```bash
kubectl get pods -n kube-system | grep -E 'flannel|kube-proxy'
```

---

## Check Postgres Endpoints

```bash
kubectl get endpoints awx-demo-postgres-13 -n awx
```

---

## Check Pod Placement

```bash
kubectl get pods -n awx -o wide
```

---

# Section 9 – Manual Database Host Patch (Last Resort)

> [!WARNING]
> Only use this procedure when DNS resolution is broken and AWX cannot reach PostgreSQL.

### Patch Secret

```bash
kubectl patch secret awx-demo-app-credentials -n awx \
-p "{\"data\":{\"host\":\"$(echo -n '10.244.2.7' | base64)\"}}"
```

---

## Restart AWX Pods

```bash
kubectl delete pod -n awx \
-l "app.kubernetes.io/managed-by=awx-operator"
```

---

# Validation Checklist

## Kubernetes

* [ ] Node Ready
* [ ] Containerd Running
* [ ] Kubelet Running

## Networking

* [ ] Flannel Running
* [ ] CoreDNS Running
* [ ] Pod Networking Functional

## Storage

* [ ] Local Path Provisioner Running
* [ ] StorageClass Set as Default

## AWX

* [ ] Operator Running
* [ ] PostgreSQL Running
* [ ] Web Pods Running
* [ ] Task Pods Running

## Access

* [ ] NodePort Reachable
* [ ] Admin Credentials Retrieved
* [ ] Login Successful

---

# Completion Criteria

The deployment is complete when:

* Kubernetes networking is healthy.
* Local-path storage is functioning.
* AWX Operator is running.
* AWX instance is deployed successfully.
* PostgreSQL is operational.
* AWX Web UI is accessible via NodePort.
* Admin login is successful.
* AWX is ready for project, inventory, and job template configuration.
