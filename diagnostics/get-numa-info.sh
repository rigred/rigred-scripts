#!/usr/bin/env bash
# =============================================================================
#  get_numa_info.sh — Collect a comprehensive NUMA topology report
#
#  Author  : Rigo Reddig
#  Version : 1.5.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.5.0"

###############################################################################
# Error handling & usage
###############################################################################
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

Options:
  -o, --output FILE   Write the report to FILE instead of stdout
  -V, --version       Show script version and exit
  -h, --help          Show this help message and exit
EOF
}

need_tool() { command -v "$1" &>/dev/null || { echo "Missing tool: $1"; exit 1; }; }

###############################################################################
# CLI parsing
###############################################################################
OUTPUT_FD=1
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) exec 3>"$2"; OUTPUT_FD=3; shift 2;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *)            echo "Unknown option: $1"; usage; exit 3;;
  esac
done

###############################################################################
# Dependencies
###############################################################################
for bin in numactl lscpu gzip grep awk; do need_tool "$bin"; done
have_column=$(command -v column &>/dev/null && echo 1 || echo 0)
have_lspci=$(command -v lspci  &>/dev/null && echo 1 || echo 0)

###############################################################################
# NUMA presence check
###############################################################################
if [[ ! -d /sys/devices/system/node ]]; then
  echo "NUMA sysfs directory missing — NUMA not enabled or unavailable." >&2
  exit 2
fi

readarray -t _nodes < <(ls -d /sys/devices/system/node/node[0-9]* 2>/dev/null)
NODE_COUNT=${#_nodes[@]}
MULTI_NUMA=$(( NODE_COUNT > 1 ? 1 : 0 ))

###############################################################################
# Helpers
###############################################################################
print_header() {
  printf '\n==============================================================================\n' >&$OUTPUT_FD
  printf ' %s\n' "$1" >&$OUTPUT_FD
  printf '==============================================================================\n' >&$OUTPUT_FD
}

###############################################################################
# 1. High-level inventory
###############################################################################
print_header "1. NUMA Hardware Inventory (numactl --hardware)"
numactl --hardware >&$OUTPUT_FD

if (( MULTI_NUMA )); then
  cat >&$OUTPUT_FD <<'EOF'

NOTE: The "node distances" table expresses relative memory latency.
      10 = local node. 21 ≈ 2.1× slower than local, etc.

EOF
else
  echo -e "\nSystem reports a single NUMA node — uniform memory latency (UMA)." >&$OUTPUT_FD
fi

###############################################################################
# 2. CPU architecture / mapping
###############################################################################
print_header "2. CPU Architecture & NUMA Mapping (lscpu)"
lscpu | sed '/^$/d' >&$OUTPUT_FD
echo >&$OUTPUT_FD

###############################################################################
# 3. Kernel boot-time NUMA detection
###############################################################################
if (( MULTI_NUMA )); then
  print_header "3. Kernel Boot-Time NUMA Detection (dmesg)"
  if dmesg -T 2>/dev/null | grep -qi numa; then
    dmesg -T | grep -i numa >&$OUTPUT_FD
  else
    echo "No NUMA-related messages found in dmesg." >&$OUTPUT_FD
  fi
  echo >&$OUTPUT_FD
fi

###############################################################################
# 4. Kernel compile-time NUMA config
###############################################################################
print_header "4. Kernel NUMA Configuration Options"
cfg_file="/boot/config-$(uname -r)"
if [[ -r $cfg_file ]]; then
  echo "Reading $cfg_file" >&$OUTPUT_FD
  grep -E '^CONFIG_(X86_)?NUMA' "$cfg_file" >&$OUTPUT_FD
elif [[ -r /proc/config.gz ]]; then
  echo "Reading /proc/config.gz" >&$OUTPUT_FD
  gzip -dc /proc/config.gz | grep -E '^CONFIG_(X86_)?NUMA' >&$OUTPUT_FD
else
  echo "Kernel config not accessible." >&$OUTPUT_FD
fi
echo >&$OUTPUT_FD

###############################################################################
# 5. Raw NUMA data from /sys
###############################################################################
print_header "5. Raw NUMA Data from /sys/devices/system/node"
echo -n "Online nodes: " >&$OUTPUT_FD; cat /sys/devices/system/node/online >&$OUTPUT_FD
echo >&$OUTPUT_FD

for node in /sys/devices/system/node/node*/; do
  stat_file="${node}numastat"
  [[ -r $stat_file ]] || continue
  echo "--- $(basename "$node") ---" >&$OUTPUT_FD
  if (( have_column )); then column -t <"$stat_file" >&$OUTPUT_FD
  else cat "$stat_file" >&$OUTPUT_FD; fi
  echo >&$OUTPUT_FD
done

###############################################################################
# 6. Network device NUMA affinity
###############################################################################
print_header "6. Network Device NUMA Affinity"
for iface in /sys/class/net/*; do
  nodenum_file="$iface/device/numa_node"
  [[ -r $nodenum_file ]] || continue
  node=$(<"$nodenum_file")
  if (( node >= 0 )); then
    printf "  %-10s → NUMA node %s\n" "$(basename "$iface")" "$node" >&$OUTPUT_FD
  else
    printf "  %-10s → no specific affinity (node=%s)\n" "$(basename "$iface")" "$node" >&$OUTPUT_FD
  fi
done
echo >&$OUTPUT_FD

###############################################################################
# 7. PCIe device NUMA affinity
###############################################################################
print_header "7. PCIe Device NUMA Affinity"
shopt -s nullglob
pci_paths=(/sys/bus/pci/devices/*)
shopt -u nullglob

if (( ${#pci_paths[@]} == 0 )); then
  echo "No PCI devices visible — VM, container, or minimal kernel." >&$OUTPUT_FD
else
  declare -A node_has_dev
  for devpath in "${pci_paths[@]}"; do
    pcislot=$(basename "$devpath")
    node=$(<"$devpath/numa_node")
    (( node < 0 )) && node="N/A"

    desc=$([[ $have_lspci -eq 1 ]] && lspci -s "$pcislot" | cut -d' ' -f3- || echo "(install pciutils)")
    printf "  %-12s  node %s  %s\n" "$pcislot" "$node" "$desc" >&$OUTPUT_FD
    node_has_dev["$node"]=1
  done

  if (( MULTI_NUMA )); then
    echo >&$OUTPUT_FD
    echo "Summary: number of PCIe functions per NUMA node" >&$OUTPUT_FD
    for n in "${!node_has_dev[@]}"; do
      count=$(grep -l "^$n\$" /sys/bus/pci/devices/*/numa_node 2>/dev/null | wc -l)
      printf "  node %-3s : %d devices\n" "$n" "$count" >&$OUTPUT_FD
    done
    echo >&$OUTPUT_FD
  fi
fi

if (( MULTI_NUMA )); then
  cat >&$OUTPUT_FD <<'EOF'

TIP: For latency-sensitive or bandwidth-heavy workloads, pin threads
     to the same NUMA node as the primary NIC for maximum performance.

EOF
fi

print_header "NUMA Topology Analysis Complete"
exit 0
