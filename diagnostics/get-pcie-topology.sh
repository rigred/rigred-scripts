#!/usr/bin/env bash
# =============================================================================
#  get-pcie-topology.sh — Human-readable PCIe tree with link info & AER/ACS
#
#  Author  : Rigo Reddig
#  Version : 1.0.2  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.0.2"

trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

usage() {
cat <<EOF
Usage: ${0##*/} [OPTIONS]

  -o, --output FILE   Write report to FILE instead of stdout
  -b, --bus BUS       Filter to PCI domain/bus (e.g. 0000:03)
      --pcie-only     Omit devices that lack link attributes
  -V, --version       Show script version and exit
  -h, --help          This help
EOF
}

need() { command -v "$1" &>/dev/null || { echo "Missing tool: $1"; exit 1; }; }

# ─────────────── CLI ───────────────
OUTPUT_FD=1; BUS_FILTER=".*"; PCIE_ONLY=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) exec 3>"$2"; OUTPUT_FD=3; shift 2;;
    -b|--bus)    BUS_FILTER="$2"; shift 2;;
    --pcie-only) PCIE_ONLY=1; shift;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *) echo "Unknown option $1"; usage; exit 3;;
  esac
done

for t in lspci setpci awk; do need "$t"; done

hdr() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1" >&$OUTPUT_FD; }

# ─────────────── 1. topology tree ───────────────
hdr "1. Complete PCI Topology (lspci -tv)"
lspci -tv | grep -E "$BUS_FILTER" >&$OUTPUT_FD

# ─────────────── 2. per-device info ───────────────
hdr "2. Per-device Link Status (speed / width) and AER / ACS"

shopt -s nullglob
for dev in /sys/bus/pci/devices/*; do
  slot=$(basename "$dev")
  [[ $slot =~ $BUS_FILTER ]] || continue

  desc=$(lspci -s "$slot" | cut -d' ' -f3-)

  speed_file="$dev/current_link_speed"
  width_file="$dev/current_link_width"
  speed="N/A"; width="N/A"
  if [[ -r $speed_file && -r $width_file ]]; then
    speed=$(<"$speed_file")
    width=$(<"$width_file")
  elif (( PCIE_ONLY )); then
    continue
  fi

  aer=$(setpci -s "$slot" CAP_EXP+0x100.L 2>/dev/null || echo "N/A")
  acs=$(setpci -s "$slot" CAP_ACS+0x4.B   2>/dev/null || echo "N/A")

  # ── pretty print ──
  printf '%-12s  %s\n' "$slot" "$desc" >&$OUTPUT_FD
  printf '%-12s  speed: %-7s width: %-3s  AER: %-8s ACS: %s\n\n' \
         '' "${speed//GT\/s/}" "x${width#x}" "$aer" "$acs" >&$OUTPUT_FD
done
shopt -u nullglob

hdr "PCIe Topology Complete"
exit 0
