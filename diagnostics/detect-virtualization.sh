#!/usr/bin/env bash
# =============================================================================
#  detect-virtualization.sh — Identify hypervisor, nesting, and local guests
#
#  Version : 1.3.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.3.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

###############################################################################
# CLI
###############################################################################
OUT_FD=1
usage() { echo "Usage: ${0##*/} [-o FILE] [-V] [-h]"; }
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) exec 3>"$2"; OUT_FD=3; shift 2;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *) echo "Unknown option $1"; usage; exit 3;;
  esac
done

###############################################################################
# Helpers
###############################################################################
have() { command -v "$1" &>/dev/null; }
hdr () {
  printf '\n==============================================================================\n' >&$OUT_FD
  printf ' %s\n' "$1" >&$OUT_FD
  printf '==============================================================================\n' >&$OUT_FD
}

###############################################################################
# 1. Detect whether this OS itself is a guest
###############################################################################
hdr "1. systemd-detect-virt"
if have systemd-detect-virt; then
  systemd-detect-virt --vm --quiet && systemd-detect-virt || echo "Bare metal"
else
  echo "(systemd-detect-virt not installed)"
fi >&$OUT_FD

###############################################################################
# 2. DMI strings
###############################################################################
hdr "2. DMI Product & Manufacturer"
if have dmidecode; then
  for k in system-product-name system-manufacturer; do
    v=$(dmidecode -s "$k" 2>/dev/null || true)
    [[ -n $v ]] && printf "%-14s: %s\n" "${k/system-/}" "$v" >&$OUT_FD
  done
else
  echo "(dmidecode missing)" >&$OUT_FD
fi

###############################################################################
# 3. CPU vendor & nested-virt flags
###############################################################################
hdr "3. CPU & Nested Virtualisation Flags"
if have lscpu; then
  lscpu | grep -E '^(Architecture|Vendor ID|Hypervisor vendor|Virtualization type):' >&$OUT_FD
  flags=$(lscpu | awk -F: '/^Flags/{print $2}')
  for f in vmx svm hypervisor; do
    [[ $flags == *$f* ]] && echo "Flag present : $f" >&$OUT_FD
  done
else
  echo "(lscpu missing)" >&$OUT_FD
fi

###############################################################################
# 4. lshw short hint
###############################################################################
if have lshw; then
  hdr "4. lshw system-vendor extract"
  lshw -class system 2>/dev/null | grep -E 'product:|vendor:' | sed 's/^/  /' >&$OUT_FD
fi

###############################################################################
# 5. Hosted VMs / Containers on this machine
###############################################################################
hdr "5. Hosted VMs / Containers"

guest_found=0

# --- QEMU/KVM processes ------------------------------------------------------
qemu_p=$(pgrep -f "^/.*qemu-system" || true)
if [[ -n $qemu_p ]]; then
  echo "QEMU/KVM VMs running (PIDs):" >&$OUT_FD
  ps -p "$qemu_p" -o pid,cmd --no-headers | sed 's/^/  /' >&$OUT_FDi
  guest_found=1
fi

# libvirt domains
if have virsh && virsh list --all &>/dev/null; then
  echo "libvirt domains:" >&$OUT_FD
  virsh list --all | sed 's/^/  /' >&$OUT_FD
  guest_found=1
fi

# systemd-nspawn / machined
if have machinectl; then
  mc=$(machinectl list --no-pager --no-legend || true)
  [[ -n $mc ]] && { echo "systemd-nspawn machines:"; echo "$mc"; } >&$OUT_FD
  [[ -n $mc ]] && guest_found=1
fi

# Docker / containerd / Podman
for ctool in docker podman; do
  if have "$ctool" && "$ctool" ps --format '{{.Names}}' &>/dev/null; then
    cnt=$("$ctool" ps --format '{{.Names}}')
    [[ -n $cnt ]] && { echo "Running $ctool containers:"; echo "$cnt" | sed 's/^/  /'; } >&$OUT_FD
    [[ -n $cnt ]] && guest_found=1
  fi
done

# LXC / LXD
if have lxc-ls; then
  lxc=$(lxc-ls --running 2>/dev/null || true)
  [[ -n $lxc ]] && { echo "Running LXC containers:"; echo "$lxc" | sed 's/^/  /'; } >&$OUT_FD
  [[ -n $lxc ]] && guest_found=1
fi
if have lxc && lxc list -c ns --format csv &>/dev/null; then
  lxd=$(lxc list -c ns --format csv | awk -F, '$2=="RUNNING"{print $1}')
  [[ -n $lxd ]] && { echo "Running LXD containers:"; echo "$lxd" | sed 's/^/  /'; } >&$OUT_FD
  [[ -n $lxd ]] && guest_found=1
fi

# No guests?
# nothing matched at all?
if (( guest_found == 0 )); then
  echo "(no local VMs or containers detected)" >&$OUT_FD
fi

hdr "Virtualisation detection complete"
exit 0



