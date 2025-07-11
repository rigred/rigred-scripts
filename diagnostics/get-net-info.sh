#!/usr/bin/env bash
# =============================================================================
#  get-net-info.sh — NIC link, offload, IRQ affinity, RSS queues
#
#  Author  : Rigo Reddig
#  Version : 1.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.0.0"

trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR
usage() {
  cat <<EOF
Usage: ${0##*/} [-o FILE]

Options:
  -o FILE        Output file
  -V             Version
  -h             Help
EOF
}
need_tool() { command -v "$1" &>/dev/null || { echo "Missing tool: $1"; exit 1; }; }

OUTPUT_FD=1
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) exec 3>"$2"; OUTPUT_FD=3; shift 2;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *) usage; exit 3;;
  esac
done

for bin in ip ethtool ss awk; do need_tool "$bin"; done

print_header() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1" >&$OUTPUT_FD; }

print_header "1. Link State & Speed"
ip -o link show | awk -F': ' '{print $2}' | while read -r ifc; do
  ethtool "$ifc" | grep -E 'Link detected|Speed|Duplex' | paste - - - | sed "s/^/$ifc: /" >&$OUTPUT_FD
done

print_header "2. Offload & Feature Flags"
for ifc in $(ls /sys/class/net); do
  printf '\n[%s]\n' "$ifc" >&$OUTPUT_FD
  ethtool -k "$ifc" | grep 'on\|off' >&$OUTPUT_FD
done

print_header "3. IRQ Affinity"
grep -E 'Local_timer|eth|mlx|enp|eno' /proc/interrupts >&$OUTPUT_FD

print_header "4. RSS Queue Count"
for ifc in /sys/class/net/*; do
  [ -d "$ifc/queues" ] || continue
  printf '%-10s : %d RX / %d TX queues\n' \
    "$(basename "$ifc")" \
    "$(ls -1 "$ifc"/queues/*rx* 2>/dev/null | wc -l)" \
    "$(ls -1 "$ifc"/queues/*tx* 2>/dev/null | wc -l)" >&$OUTPUT_FD
done

print_header "5. Listening Sockets"
ss -tunlp >&$OUTPUT_FD

print_header "Network Snapshot Complete"
exit 0
