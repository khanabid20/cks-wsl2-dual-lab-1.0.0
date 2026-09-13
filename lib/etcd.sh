#!/usr/bin/env bash
set -Eeuo pipefail

ETCD_MANIFEST=/etc/kubernetes/manifests/etcd.yaml
ETCD_PKI=/etc/kubernetes/pki/etcd
ETCD_CACERT="$ETCD_PKI/ca.crt"
ETCD_CERT="$ETCD_PKI/server.crt"
ETCD_KEY="$ETCD_PKI/server.key"
ETCD_ENDPOINT="https://127.0.0.1:2379"

_etcd_version_from_manifest(){
  [[ -f "$ETCD_MANIFEST" ]] || die "No etcd static pod at $ETCD_MANIFEST - run 'cks kubeadm-start' first (etcdctl only makes sense in kubeadm mode, not minikube)."
  grep -oP '(?<=registry\.k8s\.io/etcd:)v?[0-9]+\.[0-9]+\.[0-9]+' "$ETCD_MANIFEST" | head -1 \
    || die "Could not detect etcd version from $ETCD_MANIFEST"
}

etcdctl_install(){
  if command -v etcdctl >/dev/null; then
    echo "OK: etcdctl already installed ($(etcdctl version | head -1))"
    return
  fi
  local ver tag arch tmpd
  ver="$(_etcd_version_from_manifest)"
  [[ "$ver" == v* ]] || ver="v$ver"
  arch="$(dpkg --print-architecture)"
  log "Installing etcdctl $ver (matched to your running etcd static pod) for $arch"
  tmpd="$(mktemp -d)"
  local url="https://github.com/etcd-io/etcd/releases/download/${ver}/etcd-${ver}-linux-${arch}.tar.gz"
  curl -fL --retry 5 --retry-delay 2 "$url" -o "$tmpd/etcd.tar.gz" \
    || die "Download failed: $url"
  tar -xzf "$tmpd/etcd.tar.gz" -C "$tmpd"
  local dir; dir="$(find "$tmpd" -maxdepth 1 -type d -name "etcd-${ver}-linux-${arch}")"
  sudo install -m 0755 "$dir/etcdctl" /usr/local/bin/etcdctl
  sudo install -m 0755 "$dir/etcdutl" /usr/local/bin/etcdutl 2>/dev/null || true
  rm -rf "$tmpd"
  command -v etcdctl >/dev/null && echo "OK: $(etcdctl version | head -1)" || die "etcdctl install failed"
}

# Passthrough wrapper: fills in the exam-standard cert/key/endpoint flags so
# you can run e.g.  cks etcdctl member list
#                    cks etcdctl snapshot save /tmp/snap.db
etcdctl_run(){
  command -v etcdctl >/dev/null || die "etcdctl not installed. Run: cks etcdctl-install"
  [[ -r "$ETCD_CACERT" && -r "$ETCD_CERT" && -r "$ETCD_KEY" ]] \
    || die "etcd certs not readable at $ETCD_PKI (try with sudo, or verify kubeadm mode is running)."
  ETCDCTL_API=3 sudo -E etcdctl \
    --endpoints="$ETCD_ENDPOINT" \
    --cacert="$ETCD_CACERT" \
    --cert="$ETCD_CERT" \
    --key="$ETCD_KEY" \
    "$@"
}

etcdctl_status(){
  echo "=== etcdctl ==="
  command -v etcdctl >/dev/null && etcdctl version || { echo "Not installed. Run: cks etcdctl-install"; return; }
  [[ -f "$ETCD_MANIFEST" ]] || { echo "etcd static pod not found - start kubeadm mode first (cks kubeadm-start)."; return; }
  echo
  echo "Trying: etcdctl member list (using $ETCD_PKI certs)"
  etcdctl_run member list -w table || echo "Could not reach etcd - is kubeadm mode running? (cks kubeadm-status)"
}
