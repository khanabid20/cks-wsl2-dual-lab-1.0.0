# cks-wsl2-dual-lab: security-tools addon

Adds Trivy (image scanning), Falco (runtime security), and an AppArmor
diagnostic to the existing `cks` command, in the same style as the base lab.

## Install

Requires the base `cks-wsl2-dual-lab` already installed (`cks doctor` works).

```bash
cd cks-security-addon
sudo ./install-addon.sh
cks security-install
cks security-status
```

## What you get

- `cks security-install` — installs Trivy and Falco via their official
  signed apt repos, then tries to start Falco with the modern eBPF driver.
- `cks security-status` — one-shot status of trivy/falco/apparmor.
- `cks trivy-scan <image>` — e.g. `cks trivy-scan nginx:1.25`.
- `cks falco-status`
- `cks apparmor-status`

## Honest WSL2 constraints (read before filing a bug)

- **Trivy**: works fully. No kernel dependency.
- **Falco**: the kernel-module and legacy-eBPF drivers do not work on the
  stock Microsoft WSL2 kernel. The installer forces the **modern eBPF**
  driver, which needs kernel BTF support. It may or may not load depending
  on your exact WSL2/Windows kernel build — `cks security-install` tells you
  which happened. This is a platform limitation, not a lab defect.
- **AppArmor**: not available on the stock WSL2 kernel at all (the LSM isn't
  compiled in, and `.wslconfig` kernel command-line flags don't activate it).
  `cks apparmor-status` explains this and points you at seccomp (which works
  fully here) as the in-lab alternative, plus a suggestion to use a real
  VM/cloud instance for hands-on AppArmor enforcement specifically.

## Uninstall

```bash
sudo apt-get remove -y trivy falco
sudo rm -f /etc/apt/sources.list.d/trivy.list /etc/apt/sources.list.d/falcosecurity.list
sudo rm -f /etc/cks-wsl2-dual-lab/security.sh
```

(`cks` itself reverts to the base command set once `security.sh` is gone,
though the `security-*` entries in its help text will error until you
reinstall the base `bin/cks` from the original package.)
