#!/usr/bin/env bash
set -Eeuo pipefail
log(){ echo; echo "[CKS] $*"; }
die(){ echo "[CKS][ERROR] $*" >&2; exit 1; }
doctor(){
  echo "=== CKS WSL2 Lab Doctor ==="
  [[ "$(ps -p 1 -o comm=)" == systemd ]] && echo "OK: systemd" || { echo "FAIL: systemd"; return 1; }
  docker info >/dev/null 2>&1 && echo "OK: Docker" || { echo "FAIL: Docker"; return 1; }
  command -v minikube >/dev/null && echo "OK: Minikube" || { echo "FAIL: Minikube"; return 1; }
  command -v kubeadm >/dev/null && echo "OK: kubeadm $(kubeadm version -o short)" || { echo "FAIL: kubeadm"; return 1; }
  systemctl is-active --quiet containerd && echo "OK: containerd" || { echo "FAIL: containerd"; return 1; }
  grep -q 'SystemdCgroup = true' /etc/containerd/config.toml 2>/dev/null && echo "OK: containerd systemd cgroups" || { echo "FAIL: containerd systemd cgroups"; return 1; }
  if awk 'NR>1 && NF{exit 0} END{exit 1}' /proc/swaps; then echo "FAIL: swap enabled"; return 1; else echo "OK: swap disabled"; fi
  echo "All required checks passed."
}
