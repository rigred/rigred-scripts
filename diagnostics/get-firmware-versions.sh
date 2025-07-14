#!/usr/bin/env bash
# =============================================================================
#  get-firmware-versions.sh — Enumerate platform & device firmware
#
#  Author  : Rigo Reddig
#  Version : 1.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.0.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

usage() { echo "Usage: ${0##*/} [-o FILE]"; }

need_tool() { command -v "$1" &>/dev/null || { echo "Missing tool: $1"; exit 1; }; }

OUTPUT_FD=1
[[ $# -gt 0 && $1 =~ -o|--output ]] && { exec 3>"$2"; OUTPUT_FD=3; shift 2; }
[[ $# -gt 0 && $1 == "-V" ]] && { echo "$VERSION"; exit 0; }

need_tool dmidecode
have_fwupdmgr=$(command -v fwupdmgr &>/dev/null && echo 1 || echo 0)
have_ipmitool=$(command -v ipmitool &>/dev/null && echo 1 || echo 0)

print_header() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1" >&$OUTPUT_FD; }

print_header "1. BIOS / UEFI"
dmidecode -t bios >&$OUTPUT_FD

print_header "2. Baseboard"
dmidecode -t baseboard >&$OUTPUT_FD

if (( have_fwupdmgr )); then
  print_header "3. fwupdmgr get-devices"
  fwupdmgr get-devices >&$OUTPUT_FD
fi

if (( have_ipmitool )); then
  print_header "4. BMC"
  ipmitool mc info >&$OUTPUT_FD || echo "IPMI not accessible." >&$OUTPUT_FD
fi

print_header "Firmware Inventory Complete"
exit 0

