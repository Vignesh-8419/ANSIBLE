# 1️⃣ Stop Firewall, Flush iptables, Disable SELinux (all nodes)
systemctl stop firewalld
systemctl disable firewalld
iptables -F
setenforce 0

# 2️⃣ Kubernetes Initialization (Control-plane only)
kubeadm init --pod-network-cidr=10.244.0.0/16
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 2a️⃣ Join Worker Nodes (run on each worker)
kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# 3️⃣ Install Flannel CNI (control-plane node)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl get daemonset kube-flannel-ds -n kube-flannel
kubectl get pods -n kube-flannel -o wide

# 4️⃣ Install Local Path Provisioner (for test PVCs)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass

# 5️⃣ Install Longhorn (for production PVs)
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
kubectl get pods -n longhorn-system -w
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80

# 6️⃣ Deploy AWX Operator
kubectl create namespace awx
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml
kubectl get pods -n awx

# 7️⃣ Deploy AWX Instance
cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
  namespace: awx
spec:
  service_type: NodePort
EOF
kubectl get pods -n awx -o wide
kubectl get svc -n awx

# 8️⃣ Verify connectivity with busybox pod
kubectl run -it --rm busybox --image=busybox --restart=Never -- sh
ping 10.96.0.1

# 9️⃣ Test PVC + Pod with Longhorn
kubectl apply -f test-pvc.yaml
kubectl get pvc test-pvc -w
kubectl apply -f test-pod.yaml
kubectl get pods -o wide
kubectl exec -it test-pod -- sh
echo "test" > /data/testfile
cat /data/testfile

# 🔧 Troubleshooting (if Longhorn CSI pods stuck)
sudo ctr images pull docker.io/longhornio/csi-node-driver-registrar:v2.14.0-20250826
sudo ctr images pull docker.io/longhornio/longhorn-manager:master-head
kubectl delete pod -n longhorn-system --all
kubectl get pods -n longhorn-system -w

# 🔑 Access AWX UI
kubectl get svc -n awx
# Use: http://<any-node-ip>:<NodePort>
