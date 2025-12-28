AWX Production Migration Commands – Single Box
1️⃣ Stop & disable firewall
systemctl stop firewalld
systemctl disable firewalld
iptables -F
setenforce 0

2️⃣ Kubernetes initialization
kubeadm init --pod-network-cidr=10.244.0.0/16
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

3️⃣ Install Flannel CNI
kubectl delete namespace kube-flannel --ignore-not-found
kubectl delete clusterrole flannel --ignore-not-found
kubectl delete clusterrolebinding flannel --ignore-not-found
kubectl delete serviceaccount flannel --ignore-not-found
kubectl delete configmap kube-flannel-cfg --ignore-not-found -n kube-system

kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl get daemonset kube-flannel-ds -n kube-flannel
kubectl get pods -n kube-flannel -o wide

4️⃣ Install Local Path Provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass

5️⃣ Deploy AWX Operator
kubectl create namespace awx
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml
kubectl get pods -n awx

6️⃣ Deploy AWX Instance
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

7️⃣ Verify connectivity (busybox test pod)
kubectl run -it --rm busybox --image=busybox --restart=Never -- sh
ping 10.96.0.1

8️⃣ Longhorn (optional for prod PVs)
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
kubectl get pods -n longhorn-system
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80

9️⃣ Cleanup & pod restart (if needed)
kubectl delete pod -n longhorn-system --all
kubectl get pods -n longhorn-system -w

10️⃣ Access AWX UI
# Example NodePort
http://<node-ip>:31118
