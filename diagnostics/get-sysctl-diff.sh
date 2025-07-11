#!/usr/bin/env bash
# =============================================================================
#  get-sysctl-diff.sh — Diff runtime sysctl values against distro defaults
#
#  Author  : Rigo Reddig
#  Version : 1.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail; IFS=$'\n\t'
VERSION="1.0.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

usage() { echo "Usage: ${0##*/} [-o FILE]"; }
need_tool() { command -v "$1" &>/dev/null || { echo "Missing tool: $1"; exit 1; }; }

OUTPUT_FD=1
[[ $# -gt 0 && $1 =~ -o|--output ]] && { exec 3>"$2"; OUTPUT_FD=3; shift 2; }
[[ $# -gt 0 && $1 == "-V" ]] && { echo "$VERSION"; exit 0; }

need_tool sysctl diff

print_header() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1" >&$OUTPUT_FD; }

TMP=$(mktemp)
sysctl -a --ignore 2>/dev/null | sort > "$TMP"

print_header "1. Runtime vs Packaged Default (system-provided *.conf)"
for conf in /usr/lib/sysctl.d/*.conf; do
  awk '/^[^#].*=/ {gsub(/ /,"");print}' "$conf"
done | sort > "$TMP.defaults"

diff -u "$TMP.defaults" "$TMP" >&$OUTPUT_FD || true
rm -f "$TMP" "$TMP.defaults"

print_header "Sysctl Drift Check Complete"
exit 0

