# CKS WSL2 Dual Lab

Fast daily CKS practice plus a real kubeadm control-plane lab, using your existing Docker installation.

## Architecture

- Fast mode: Minikube + Docker, profile `cks-fast`
- Security/control-plane mode: kubeadm + containerd, single node
- Kubernetes target: v1.35
- Calico: v3.32.2 for kubeadm mode

## Install

From Ubuntu WSL2:

```bash
cd ~/cks-wsl2-dual-lab-1.0.0
sudo ./install.sh
exec bash
cks doctor
```

The installer refuses to continue if systemd is not PID 1 or Docker is not usable.

## Daily fast lab

```bash
cks start
kubectl get nodes
kubectl get pods -A
cks reset
```

## Real control-plane lab

```bash
cks kubeadm-start
cks kubeadm-status
```

This exposes:

```text
/etc/kubernetes/manifests/kube-apiserver.yaml
/etc/kubernetes/manifests/etcd.yaml
/var/lib/kubelet/
/etc/kubernetes/
/var/log/kubernetes/
```

## Audit logging practice

```bash
cks audit-on
kubectl get pods -A
kubectl get secrets -A
cks audit-status
sudo tail -f /var/log/kubernetes/audit.log
cks audit-off
```

`audit-on` backs up the original kube-apiserver manifest and waits for `/readyz`
before reporting success.

## Destructive commands

`cks reset` deletes only the Minikube profile.

`cks kubeadm-reset` destroys the kubeadm cluster after an explicit `YES`
confirmation.

## Requirements

- Ubuntu WSL2
- sudo
- working Docker from WSL2
- systemd enabled in WSL2
- internet
- 4 CPUs / 8 GB RAM recommended

If systemd is not enabled, add this to `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Then from Windows PowerShell run:

```powershell
wsl --shutdown
```

Start Ubuntu again and rerun the installer.

## Why two modes?

Minikube is intentionally fast and is ideal for most CKS topics. kubeadm is
used for exercises that require the actual control-plane files and services,
such as API-server flags, audit logging, etcd and kubelet configuration.

A single WSL2 distro is not a replacement for a multi-node production lab.
It is deliberately the smallest reliable environment for the CKS tasks that
matter most.

## Runtime note

Fast mode uses the existing Docker Engine through Minikube. The kubeadm specialist mode uses the host's containerd CRI socket at `/run/containerd/containerd.sock`; it does not use Docker Engine as kubeadm's runtime. The installer configures that containerd service with CRI enabled and `SystemdCgroup = true`.

On WSL2, Windows/WSL configuration can expose swap again after a restart. `cks kubeadm-start` therefore runs `swapoff -a` before kubeadm initialization and refuses to continue if swap remains enabled.
