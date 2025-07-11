#!/usr/bin/env bash
# =============================================================================
#  get-storage-health.sh — concise SMART / NVMe / RAID / ZFS report
#
#  Version : 1.1.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.1.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

usage() {
  cat <<EOF
Usage: ${0##*/} [-o FILE]
  -o, --output FILE   Write report to FILE instead of stdout
  -V, --version       Show script version and exit
  -h, --help          This help

Only whole, non-zero-byte block devices are probed.  Requires smartctl;
optionally nvme-cli, mdadm, zpool.
EOF
}

###############################################################################
# CLI
###############################################################################
OUT_FD=1
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) exec 3>"$2"; OUT_FD=3; shift 2;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *)            echo "Unknown option $1"; usage; exit 3;;
  esac
done

###############################################################################
# deps
###############################################################################
need() { command -v "$1" &>/dev/null || { echo "Missing tool: $1"; exit 1; }; }
need smartctl
need lsblk
have_nvme=$(command -v nvme   &>/dev/null && echo 1 || echo 0)
have_mdadm=$(command -v mdadm &>/dev/null && echo 1 || echo 0)
have_zpool=$(command -v zpool &>/dev/null && echo 1 || echo 0)

hdr() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1" >&$OUT_FD; }

###############################################################################
# 1. drive list – skip 0-byte “slots”
###############################################################################
hdr "1. Detected Drives (non-zero capacity)"
lsblk -d -o NAME,TYPE,SIZE,MODEL,SERIAL |
  awk '$3!="0B" && $2=="disk"' >&$OUT_FD

mapfile -t drives < <(lsblk -dno NAME,SIZE | awk '$2!="0B"{print "/dev/"$1}')

###############################################################################
# 2. SMART / NVMe logs
###############################################################################
for dev in "${drives[@]}"; do
  hdr "2. ${dev} — Health"
  if [[ $dev == /dev/nvme* && $have_nvme -eq 1 ]]; then
    nvme smart-log "$dev" 2>/dev/null || echo "nvme failed on $dev" >&$OUT_FD
  else
    smartctl -x "$dev" 2>/dev/null || echo "smartctl skipped/failed on $dev" >&$OUT_FD
  fi
done

###############################################################################
# 3. mdraid
###############################################################################
hdr "3. mdadm Arrays"
if (( have_mdadm )) && grep -q ^md /proc/mdstat 2>/dev/null; then
  mdadm --detail --scan >&$OUT_FD
  for md in /dev/md*; do mdadm --detail "$md" >&$OUT_FD; done
else
  echo "(no mdraid arrays)" >&$OUT_FD
fi

###############################################################################
# 4. ZFS
###############################################################################
hdr "4. ZFS Pools"
if (( have_zpool )) && zpool list -H >/dev/null 2>&1; then
  zpool status -xv >&$OUT_FD
else
  echo "(no ZFS pools)" >&$OUT_FD
fi

hdr "Storage health report complete"
exit 0

