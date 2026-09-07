#!/usr/bin/env bash
set -Eeuo pipefail
CRISOCK=unix:///run/containerd/containerd.sock
CIDR=192.168.0.0/16
MARKER=/etc/cks-kubeadm-initialized

kubeadm_start(){
  [[ "$(ps -p 1 -o comm=)" == systemd ]] || die "systemd is required."
  sudo systemctl is-active --quiet containerd || { sudo systemctl restart containerd; sudo systemctl is-active --quiet containerd || die "containerd is not running."; }
  sudo test -S /run/containerd/containerd.sock || die "containerd socket missing."

  # WSL2/Windows can expose a swap device even after installation-time swapoff.
  # kubelet defaults to fail when swap is enabled, so enforce the CKS lab invariant here.
  sudo swapoff -a || true
  if sudo swapon --show | awk 'NR>1 && NF{found=1} END{exit found ? 0 : 1}'; then
    die "Swap is still enabled. Run 'sudo swapoff -a' and retry."
  fi

  if [[ -f /etc/kubernetes/admin.conf ]]; then
    if kubectl --kubeconfig=/etc/kubernetes/admin.conf auth can-i get nodes >/dev/null 2>&1; then
      kubeadm_status
      return
    fi
    die "A partial kubeadm initialization exists but kubernetes-admin is not authorized. Run 'cks kubeadm-reset' and retry."
  fi

  log "Initializing kubeadm control plane"
  sudo kubeadm init --kubernetes-version="$(kubeadm version -o short)" \
    --pod-network-cidr="$CIDR" --cri-socket="$CRISOCK" --upload-certs

  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

  log "Installing Calico v3.32.2"
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/calico.yaml
  kubectl wait --for=condition=Ready node --all --timeout=300s
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1 || true
  sudo touch "$MARKER"
  sudo chmod 0600 "$MARKER"
  kubectl get nodes -o wide
  kubectl get pods -A
}

kubeadm_status(){
  echo "=== kubeadm lab ==="
  [[ -f /etc/kubernetes/admin.conf ]] || { echo "Not initialized."; return; }
  kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide || true
  kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A || true
  echo; ls -la /etc/kubernetes/manifests 2>/dev/null || true
}

kubeadm_reset(){
  [[ -f /etc/kubernetes/admin.conf || -f "$MARKER" ]] || { echo "Not initialized."; return; }
  read -r -p "DESTROY kubeadm cluster? Type YES: " x
  [[ "$x" == YES ]] || { echo Cancelled.; return; }
  sudo kubeadm reset -f --cri-socket="$CRISOCK" || true
  sudo rm -rf /etc/kubernetes /var/lib/etcd /etc/cni/net.d/* /var/lib/cni/*
  rm -rf "$HOME/.kube"
  sudo systemctl restart containerd
  sudo rm -f "$MARKER"
  echo "kubeadm lab removed."
}
