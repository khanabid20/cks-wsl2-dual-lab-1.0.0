#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die(){ echo "[CKS-ADDON][ERROR] $*" >&2; exit 1; }
log(){ echo; echo "[CKS-ADDON] $*"; }

[[ $EUID -eq 0 ]] || die "Run: sudo ./install-addon.sh"
[[ -d /etc/cks-wsl2-dual-lab ]] || die "Base lab not found at /etc/cks-wsl2-dual-lab. Install cks-wsl2-dual-lab first (sudo ./install.sh from the original package)."
[[ -f /usr/local/bin/cks ]] || die "cks command not found at /usr/local/bin/cks. Install the base lab first."

log "Installing lib/security.sh"
install -m 0644 "$BASE/lib/security.sh" /etc/cks-wsl2-dual-lab/security.sh

log "Installing lib/etcd.sh"
install -m 0644 "$BASE/lib/etcd.sh" /etc/cks-wsl2-dual-lab/etcd.sh

log "Replacing /usr/local/bin/cks with the security-aware version"
install -m 0755 "$BASE/bin/cks" /usr/local/bin/cks

echo
echo "[CKS-ADDON] Done. New commands:"
echo "  cks security-install   # installs Trivy + Falco (best-effort on WSL2)"
echo "  cks security-status    # trivy/falco/apparmor status + WSL2 caveats"
echo "  cks trivy-scan <image>"
echo "  cks falco-status"
echo "  cks apparmor-status"
echo "  cks apparmor-enable"
echo "  cks etcdctl-install    # matched to your running etcd version (kubeadm mode)"
echo "  cks etcdctl-status"
echo "  cks etcdctl <args...>"
echo
echo "Run 'cks security-install' next."
