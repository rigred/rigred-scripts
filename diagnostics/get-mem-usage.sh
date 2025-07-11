#!/usr/bin/env bash
# =============================================================================
#  get-mem-usage.sh — High-resolution memory pressure snapshot
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
[[ $# -gt 0 && $1 == -* ]] && { [[ $1 =~ -o|--output ]] && exec 3>"$2" && OUTPUT_FD=3 && shift 2; }
[[ $# -gt 0 && $1 == "-V" ]] && { echo "$VERSION"; exit 0; }

for bin in free awk; do need_tool "$bin"; done
have_smem=$(command -v smem &>/dev/null && echo 1 || echo 0)
have_numastat=$(command -v numastat &>/dev/null && echo 1 || echo 0)

print_header() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1" >&$OUTPUT_FD; }

print_header "1. free -h"
free -h >&$OUTPUT_FD

print_header "2. /proc/meminfo (top 20)"
head -20 /proc/meminfo >&$OUTPUT_FD

(( have_smem )) && { print_header "3. smem (top 10)"; smem -r -k | sort -nrk 7 | head >&$OUTPUT_FD; }

(( have_numastat )) && { print_header "4. numastat"; numastat -s >&$OUTPUT_FD; }

swappath=$(swapon --noheadings --bytes --raw 2>/dev/null | awk '{print $1}')
if [[ -n $swappath ]]; then
  print_header "5. Swap Usage (per process)"
  awk '{sw[$1]+=$3} END {for(p in sw) printf "%-8s %s\n",p,sw[p]}' /proc/*/status 2>/dev/null | sort -nrk2 | head >&$OUTPUT_FD || true
fi

print_header "Memory Snapshot Complete"
exit 0

