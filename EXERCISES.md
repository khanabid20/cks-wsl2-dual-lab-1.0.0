# CKS exercises

## Fast mode

```bash
cks start
```

Practice RBAC, ServiceAccounts, Secrets, securityContext, capabilities,
seccomp, NetworkPolicy, Pod Security and workload troubleshooting.

Reset:

```bash
cks reset
```

## Control-plane mode

```bash
cks kubeadm-start
```

Inspect:

```bash
sudo less /etc/kubernetes/manifests/kube-apiserver.yaml
sudo less /etc/kubernetes/manifests/etcd.yaml
sudo systemctl cat kubelet
```

## Audit

```bash
cks audit-on
kubectl get pods -A
kubectl get secrets -A
kubectl create namespace audit-demo
kubectl delete namespace audit-demo
sudo tail -f /var/log/kubernetes/audit.log
cks audit-status
cks audit-off
```

## Recovery

If you intentionally break a control-plane manifest:

```bash
kubectl get --raw=/readyz
```

If you need a clean control-plane lab:

```bash
cks kubeadm-reset
cks kubeadm-start
```

The objective is not to memorize one file. Practice locating the setting,
changing it safely, and verifying the result.
