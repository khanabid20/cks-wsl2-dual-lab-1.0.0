#!/usr/bin/env bash
set -Eeuo pipefail
M=/etc/kubernetes/manifests/kube-apiserver.yaml
B=/etc/kubernetes/manifests/kube-apiserver.yaml.cks-backup
D=/etc/kubernetes/audit
P=$D/policy.yaml
L=/var/log/kubernetes/audit.log
audit_on(){
  [[ -f /etc/kubernetes/admin.conf ]] || die "Run cks kubeadm-start first."
  [[ -f "$M" ]] || die "kube-apiserver manifest missing."
  grep -q -- '--audit-policy-file=' "$M" && { audit_status; return; }
  mkdir -p "$D" /var/log/kubernetes
  cat >"$P" <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["pods","secrets","configmaps"]
- level: Metadata
  resources:
  - group: "rbac.authorization.k8s.io"
    resources: ["roles","rolebindings","clusterroles","clusterrolebindings"]
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods/exec","pods/portforward"]
- level: Metadata
EOF
  chmod 0640 "$P"
  cp -a "$M" "$B"
  python3 - "$M" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
flags=[
"    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml",
"    - --audit-log-path=/var/log/kubernetes/audit.log",
"    - --audit-log-maxage=30",
"    - --audit-log-maxbackup=10",
"    - --audit-log-maxsize=100",
]
if "--audit-policy-file=" not in s:
    lines=s.splitlines()
    i=next(i for i,x in enumerate(lines) if x.strip()=="command:")
    lines[i+1:i+1]=flags
    s="\n".join(lines)+"\n"
if "mountPath: /etc/kubernetes/audit" not in s:
    lines=s.splitlines()
    i=next(i for i,x in enumerate(lines) if x.strip()=="volumeMounts:")
    ind=lines[i][:len(lines[i])-len(lines[i].lstrip())]
    lines[i+1:i+1]=[
      ind+"- mountPath: /etc/kubernetes/audit",
      ind+"  name: audit-policy",
      ind+"- mountPath: /var/log/kubernetes",
      ind+"  name: audit-log"]
    s="\n".join(lines)+"\n"
if "    name: audit-policy" not in s[s.find("  volumes:"):]:
    lines=s.splitlines()
    i=next(i for i,x in enumerate(lines) if x.strip()=="volumes:" and x.startswith("  "))
    lines[i+1:i+1]=[
      "  - hostPath:","      path: /etc/kubernetes/audit","      type: DirectoryOrCreate","    name: audit-policy",
      "  - hostPath:","      path: /var/log/kubernetes","      type: DirectoryOrCreate","    name: audit-log"]
    s="\n".join(lines)+"\n"
p.write_text(s)
PY
  for i in $(seq 1 60); do
    kubectl --kubeconfig=/etc/kubernetes/admin.conf get --raw=/readyz >/dev/null 2>&1 && { audit_status; return; }
    sleep 2
  done
  die "API server did not recover. Original manifest is $B"
}
audit_status(){
  echo "=== audit ==="
  grep -E -- '--audit-(policy-file|log-path|maxage|maxbackup|maxsize)=' "$M" 2>/dev/null || echo "Audit flags not present."
  ls -l "$P" "$L" 2>/dev/null || true
  [[ -f "$L" ]] && tail -n 5 "$L" || true
}
audit_off(){
  [[ -f "$B" ]] || die "No audit backup exists."
  cp -a "$B" "$M"
  rm -rf "$D"
  for i in $(seq 1 60); do
    kubectl --kubeconfig=/etc/kubernetes/admin.conf get --raw=/readyz >/dev/null 2>&1 && { echo "Audit disabled."; return; }
    sleep 2
  done
  die "API server did not recover after audit-off."
}
