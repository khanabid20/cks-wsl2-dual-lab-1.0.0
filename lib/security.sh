#!/usr/bin/env bash
set -Eeuo pipefail

# --- Trivy: image / config / secret scanning -------------------------------
trivy_install(){
  if command -v trivy >/dev/null; then
    echo "OK: trivy already installed ($(trivy --version | head -1))"
    return
  fi
  log "Installing Trivy via the official signed apt repo"
  sudo curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/trivy.gpg
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
    | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y trivy
  command -v trivy >/dev/null && echo "OK: trivy $(trivy --version | head -1)" || die "trivy install failed"
}

trivy_status(){
  echo "=== trivy ==="
  command -v trivy >/dev/null && trivy --version || echo "Not installed. Run: cks security-install"
}

trivy_scan(){
  command -v trivy >/dev/null || die "trivy not installed. Run: cks security-install"
  local image="${1:?Usage: cks trivy-scan <image:tag>}"
  trivy image --severity HIGH,CRITICAL "$image"
}

# --- Falco: runtime / syscall security --------------------------------------
falco_install(){
  if ! command -v falco >/dev/null; then
    log "Installing Falco via the official signed apt repo"
    sudo curl -fsSL https://falco.org/repo/falcosecurity-packages.asc \
      | sudo gpg --dearmor --yes -o /usr/share/keyrings/falco-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
      | sudo tee /etc/apt/sources.list.d/falcosecurity.list >/dev/null
    sudo apt-get update -y
    DEBIAN_FRONTEND=noninteractive FALCO_FRONTEND=noninteractive sudo apt-get install -y falco
  else
    echo "OK: falco already installed ($(falco --version | head -1))"
  fi

  log "Forcing the modern eBPF driver (kernel-module and legacy eBPF drivers do not work on the stock WSL2 kernel)"
  if [[ -f /etc/falco/falco.yaml ]]; then
    if grep -q '^engine:' /etc/falco/falco.yaml; then
      sudo python3 - <<'PY'
from pathlib import Path
p = Path("/etc/falco/falco.yaml")
lines = p.read_text().splitlines()
out, in_engine = [], False
for l in lines:
    if l.startswith("engine:"):
        in_engine = True
        out.append(l)
        continue
    if in_engine and l.startswith("  kind:"):
        out.append("  kind: modern_ebpf")
        in_engine = False
        continue
    if in_engine and not l.startswith(" "):
        in_engine = False
    out.append(l)
p.write_text("\n".join(out) + "\n")
PY
    else
      printf '\nengine:\n  kind: modern_ebpf\n' | sudo tee -a /etc/falco/falco.yaml >/dev/null
    fi
  fi

  echo
  echo "Testing whether the modern eBPF driver actually loads on this kernel..."
  if sudo timeout 10 falco --modern-bpf -M 6 >/tmp/falco-test.log 2>&1; then
    echo "OK: Falco started with the modern eBPF driver. You can run it as a normal foreground process:"
    echo "    sudo falco --modern-bpf"
  else
    cat <<EOF
WARN: Falco could NOT start with the modern eBPF driver on this kernel.
      This is a WSL2 kernel limitation, not a bug in this lab. Log: /tmp/falco-test.log

      Why: the modern eBPF driver needs kernel BTF metadata compiled in
      (CONFIG_DEBUG_INFO_BTF), and the kernel-module / legacy-eBPF drivers
      need module-build support or headers matching 'uname -r'
      ($(uname -r)), neither of which the stock Microsoft WSL2 kernel ships
      reliably. This varies by WSL2/Windows build, so it is worth retrying
      after a Windows/WSL kernel update.

      For CKS runtime-security practice without live enforcement here:
        - Read/write Falco rules (falco_rules.yaml) and study the syntax.
        - Use 'cks trivy-scan' and audit logging (cks audit-on) instead,
          which work fully in this lab.
        - For hands-on live Falco alerts, run it on a real Linux VM/cloud
          instance (falco.org docs) and come back here for everything else.
EOF
  fi
}

falco_status(){
  echo "=== falco ==="
  command -v falco >/dev/null || { echo "Not installed. Run: cks security-install"; return; }
  falco --version
  systemctl is-active falco >/dev/null 2>&1 \
    && echo "OK: falco service active" \
    || echo "falco service not active (expected on WSL2 unless the modern eBPF driver loaded - see 'cks security-install' output)"
}

# --- AppArmor: diagnostic + fix ---------------------------------------------
# Fix sequence confirmed working on WSL2 by:
#   https://github.com/microsoft/WSL/issues/8709#issuecomment-3195645088
_apparmor_lsm_list(){ [[ -r /sys/kernel/security/lsm ]] && cat /sys/kernel/security/lsm || true; }

apparmor_status(){
  echo "=== AppArmor (WSL2 diagnostic) ==="
  local lsm_list; lsm_list="$(_apparmor_lsm_list)"

  if [[ ",$lsm_list," == *,apparmor,* ]]; then
    echo "OK: AppArmor is active. LSM order: $lsm_list"
    command -v aa-status >/dev/null && sudo aa-status
    return
  fi

  echo "AppArmor is not currently active."
  [[ -n "$lsm_list" ]] && echo "Active LSM list: $lsm_list"
  if mountpoint -q /sys/kernel/security 2>/dev/null; then
    echo "securityfs is mounted, but apparmor is missing from the active LSM stack."
  else
    echo "securityfs is not mounted."
  fi

  cat <<'EOF'

This is fixable on many WSL2 builds (confirmed via a real user report:
https://github.com/microsoft/WSL/issues/8709#issuecomment-3195645088) by:
  1. Setting kernelCommandLine in %UserProfile%\.wslconfig so apparmor is
     first in the lsm= list
  2. Mounting securityfs at boot via /etc/fstab
  3. Reloading systemd and fully restarting WSL2 (wsl --shutdown)

Run 'cks apparmor-enable' to apply steps 1-2 automatically, then follow the
printed instructions for step 3 (must be run from Windows, not this shell).
If it still doesn't take after that, treat it as a platform limit on this
particular WSL2/Windows build and use a real VM for this one CKS topic.
EOF
}

apparmor_enable(){
  local desired="lsm=apparmor,landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,tomoyo"

  log "Locating your Windows user profile via WSL interop"
  local winprofile
  winprofile="$(powershell.exe -NoProfile -Command '$env:UserProfile' 2>/dev/null | tr -d '\r')"
  [[ -n "$winprofile" ]] || die "Could not reach powershell.exe via WSL interop. Edit %UserProfile%\\.wslconfig manually: add/update kernelCommandLine under [wsl2] to:\n  $desired"

  local wslconfig
  wslconfig="$(wslpath -u "$winprofile")/.wslconfig"
  touch "$wslconfig" 2>/dev/null || die "Could not write to $wslconfig"
  cp "$wslconfig" "$wslconfig.bak.$(date +%s)" 2>/dev/null || true

  log "Updating $wslconfig"
  if grep -q '^\[wsl2\]' "$wslconfig"; then
    if grep -q '^kernelCommandLine' "$wslconfig"; then
      sed -i "s|^kernelCommandLine.*|kernelCommandLine=$desired|" "$wslconfig"
    else
      sed -i "/^\[wsl2\]/a kernelCommandLine=$desired" "$wslconfig"
    fi
  else
    printf '\n[wsl2]\nkernelCommandLine=%s\n' "$desired" >> "$wslconfig"
  fi
  echo "OK: kernelCommandLine=$desired"

  log "Adding securityfs to /etc/fstab"
  if ! grep -q '/sys/kernel/security' /etc/fstab 2>/dev/null; then
    echo 'none     /sys/kernel/security securityfs defaults            0      0' | sudo tee -a /etc/fstab >/dev/null
    echo "OK: appended securityfs entry to /etc/fstab"
  else
    echo "OK: /etc/fstab already has a securityfs entry"
  fi

  local stray
  stray="$(awk '/^\[wsl2\]/{exit} /^[A-Za-z0-9_.]+[[:space:]]*=/{print}' "$wslconfig")"
  if [[ -n "$stray" ]]; then
    echo
    echo "WARNING: found setting(s) in $wslconfig BEFORE the active [wsl2]"
    echo "header - the WSL parser ignores anything above the section it"
    echo "belongs under, so these are currently dead (often caused by an"
    echo "earlier commented-out '#[wsl2]' line above them):"
    echo "$stray"
    echo "Open $wslconfig and move those line(s) below [wsl2] manually."
  fi

  sudo systemctl daemon-reload

  cat <<'EOF'

Config updated. Last step must be run from Windows, not inside this shell:
  1. Close this WSL terminal
  2. In PowerShell or cmd:  wsl --shutdown
  3. Reopen your Ubuntu WSL2 terminal
  4. Run:  cks apparmor-status
EOF
}
