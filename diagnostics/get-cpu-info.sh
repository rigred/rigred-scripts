#!/usr/bin/env bash
# =============================================================================
#  get-cpu-info.sh — Collect a deep CPU & microcode inventory
#
#  Author  : Rigo Reddig
#  Version : 1.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.0.0"

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

Description:
  Prints a human-readable overview of:
    • CPU model / stepping / microcode
    • Vulnerability mitigations (Spectre/L1TF/Bleeding Bit/Zenbleed/…)
    • Hybrid-core (P- vs E-core) mapping on AMD/Intel
    • Per-socket package temperature (if sensors available)
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
for bin in lscpu grep awk;        do need_tool "$bin"; done
have_cpuid=$(command -v cpuid    &>/dev/null && echo 1 || echo 0)
have_sensors=$(command -v sensors &>/dev/null && echo 1 || echo 0)

###############################################################################
# Helpers
###############################################################################
print_header() {
  printf '\n==============================================================================\n' >&$OUTPUT_FD
  printf ' %s\n' "$1" >&$OUTPUT_FD
  printf '==============================================================================\n' >&$OUTPUT_FD
}

###############################################################################
# 1. CPU basics (lscpu)
###############################################################################
print_header "1. Logical & Physical CPU Layout (lscpu)"
lscpu | sed '/^$/d' >&$OUTPUT_FD
echo >&$OUTPUT_FD

###############################################################################
# 2. Microcode & stepping info
###############################################################################
print_header "2. Per-core Stepping & Microcode ( /proc/cpuinfo )"
awk -v OFS='\t' '
  BEGIN {print "CPU","Family","Model","Stepping","uCode"} 
  /^processor/     {cpu=$3}
  /^cpu family/    {fam=$4}
  /^model[[:space:]]/ {model=$3}
  /^stepping/      {step=$3}
  /^microcode/     {ucode=$3; print cpu,fam,model,step,ucode}
' /proc/cpuinfo >&$OUTPUT_FD
echo >&$OUTPUT_FD

###############################################################################
# 3. Vulnerability flags
###############################################################################
print_header "3. Vulnerability Flags (grep -vulnerable)"
grep -E '^(bugs|Vulnerability|flags)' /proc/cpuinfo | sort -u | sed 's/^/  /' >&$OUTPUT_FD
echo >&$OUTPUT_FD

###############################################################################
# 4. Hybrid-core mapping (AMD CPPC / Intel EPP)
###############################################################################
print_header "4. Performance vs Efficiency Core Mapping"
if [[ -d /sys/devices/system/cpu ]]; then
  if [[ -d /sys/devices/system/cpu/cpu0/acpi_cppc ]]; then
    # AMD/ACPI CPPC
    for N in /sys/devices/system/cpu/cpu*/acpi_cppc/highest_perf; do
      val=$(<"$N"); cpu=${N%%/acpi_cppc/*}; cpu=${cpu##*cpu}; printf "%4s  %s\n" "$cpu" "$val"
    done | sort -nrk2 | awk 'NR==1{print "Higher = likely P-core\n"}1' >&$OUTPUT_FD
  elif [[ -r /sys/devices/system/cpu/cpu0/cpufreq/base_frequency ]]; then
    # Intel hybrid guess
    echo "Intel hybrid indication via base_frequency:" >&$OUTPUT_FD
    for N in /sys/devices/system/cpu/cpu*/cpufreq/base_frequency; do
      freq=$(<"$N"); cpu=${N%%/cpufreq/*}; cpu=${cpu##*cpu}; printf "%4s  %s\n" "$cpu" "$freq"
    done | sort -nrk2 >&$OUTPUT_FD
  else
    echo "No hybrid-core indicators found." >&$OUTPUT_FD
  fi
else
  echo "/sys missing?" >&$OUTPUT_FD
fi
echo >&$OUTPUT_FD

###############################################################################
# 5. Optional cpuid dump
###############################################################################
if (( have_cpuid )); then
  print_header "5. Raw CPUID Dump (cpuid –1)"
  cpuid -1 >&$OUTPUT_FD
else
  print_header "5. Raw CPUID Dump"
  echo "Install the 'cpuid' utility for a full register dump." >&$OUTPUT_FD
fi
echo >&$OUTPUT_FD

###############################################################################
# 6. Package temperatures (sensors)
###############################################################################
if (( have_sensors )); then
  print_header "6. CPU Package Temperatures"
  sensors | awk 'BEGIN{sec=0}/^Package id [0-9]+/{print}' >&$OUTPUT_FD
fi

print_header "CPU Inventory Complete"
exit 0
