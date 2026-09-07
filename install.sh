#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die(){ echo "[CKS][ERROR] $*" >&2; exit 1; }
log(){ echo; echo "[CKS] $*"; }

[[ $EUID -eq 0 ]] || die "Run: sudo ./install.sh"
. /etc/os-release
[[ "${ID:-}" == ubuntu || "${ID_LIKE:-}" == *ubuntu* ]] || die "Ubuntu WSL2 is required."
[[ "$(ps -p 1 -o comm=)" == systemd ]] || die "systemd is not PID 1. Enable WSL2 systemd, run 'wsl --shutdown', then retry."
command -v docker >/dev/null || die "Docker is missing. Run 'docker version' first."
docker info >/dev/null 2>&1 || die "Docker exists but is not usable by this user."
arch="$(dpkg --print-architecture)"
[[ "$arch" == amd64 || "$arch" == arm64 ]] || die "Unsupported architecture: $arch"

log "Installing prerequisites"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl gpg apt-transport-https jq conntrack socat ebtables ethtool \
  iptables iproute2 openssl python3

log "Installing Minikube"
if ! command -v minikube >/dev/null; then
  t="$(mktemp)"
  curl -fL --retry 5 --retry-delay 2 \
    https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 -o "$t"
  install -m 0755 "$t" /usr/local/bin/minikube
  rm -f "$t"
fi

log "Configuring containerd for kubeadm/CRI"
command -v containerd >/dev/null || die "containerd is missing. Docker Engine should provide containerd.io; install Docker Engine first."
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
python3 - <<'PY'
from pathlib import Path
p=Path("/etc/containerd/config.toml")
s=p.read_text()
s=s.replace("SystemdCgroup = false", "SystemdCgroup = true")
lines=[line for line in s.splitlines() if not line.lstrip().startswith("disabled_plugins") ]
p.write_text("\n".join(lines)+"\n")
PY
systemctl enable containerd
systemctl restart containerd
systemctl is-active --quiet containerd || die "containerd did not start."
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || die "containerd SystemdCgroup was not configured."

log "Configuring Kubernetes host prerequisites"
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay || true
modprobe br_netfilter || true
cat >/etc/sysctl.d/99-cks-kubernetes.conf <<'EOF'
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge-nf-call-ip6tables=1
EOF
sysctl --system >/dev/null
swapoff -a || true
sed -i -E 's@^([^#].*\sswap\s.*)$@# \1@' /etc/fstab 2>/dev/null || true

log "Installing Kubernetes 1.35 packages"
mkdir -p /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key |
  gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat >/etc/apt/sources.list.d/kubernetes.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /
EOF
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

log "Installing CNI plugins"
CNI_VERSION=v1.3.0
mkdir -p /opt/cni/bin
curl -fL --retry 5 --retry-delay 2 \
  "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${arch}-${CNI_VERSION}.tgz" |
  tar -C /opt/cni/bin -xz

log "Installing cks command"
install -d -m 0755 /etc/cks-wsl2-dual-lab
install -m 0755 "$BASE/bin/cks" /usr/local/bin/cks
install -m 0644 "$BASE/lib/"*.sh /etc/cks-wsl2-dual-lab/

log "Final doctor check"
cks doctor
echo
echo "[CKS] Installation complete."
echo "[CKS] Fast lab: cks start"
echo "[CKS] Control-plane lab: cks kubeadm-start"
