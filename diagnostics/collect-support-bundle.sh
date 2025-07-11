#!/usr/bin/env bash
# =============================================================================
#  collect-support-bundle.sh — one-click tarball of all diagnostic scripts
#
#  Version : 1.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.0.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

###############################################################################
# Config / CLI
###############################################################################
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOST=$(hostname -s)
STAMP=$(date +%Y%m%d-%H%M%S)
WORKDIR="/tmp/support-bundle-${HOST}-${STAMP}"
OUT_TAR="support-bundle-${HOST}-${STAMP}.tar.gz"

usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

  -o, --output FILE   Write bundle to FILE (default: \$PWD/${OUT_TAR})
  -k, --keep          Keep temporary workdir (for debugging)
  -V, --version       Show script version and exit
  -h, --help          This help
EOF
}

KEEP_WORK=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) OUT_TAR=$2; shift 2;;
    -k|--keep)   KEEP_WORK=1; shift;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 3;;
  esac
done

mkdir -p "$WORKDIR"

###############################################################################
# Helpers
###############################################################################
rand_tag=$(openssl rand -hex 4 2>/dev/null || echo anon)
redact() {
  # Replace hostname and RFC1918 addresses with anon tags
  sed -e "s/$(hostname -s)/host-${rand_tag}/g" \
      -e 's/\b\(10\.\|192\.168\.\|172\.\(1[6-9]\|2[0-9]\|3[01]\)\.\)[0-9.]\+\b/XXX.PRIV.IP/g'
}

run_script() {
  local script="$1" base out_file
  base=$(basename "$script" .sh)
  out_file="$WORKDIR/${base}.txt"

  printf 'Running %-30s … ' "$base"
  if "$script" &> "$out_file"; then
    printf 'done\n'
    redact <"$out_file" >"${out_file}.tmp" && mv "${out_file}.tmp" "$out_file"
  else
    printf 'FAIL (continuing)\n'
  fi
}

###############################################################################
# Execute available helper scripts
###############################################################################
echo "Collecting diagnostics into $WORKDIR"
cd "$SCRIPT_DIR"

helpers=(
  get-numa-info.sh
  get-cpu-info.sh
  get-gpu-info.sh
  get-compute-api-info.sh
  get-rendering-api-info.sh
  get-ml-stack-info.sh
  get-pcie-topology.sh
  get-storage-health.sh
  get-io-profile.sh
  get-net-info.sh
  get-mem-usage.sh
  get-firmware-versions.sh
  get-sysctl-diff.sh
  get-security-posture.sh
  detect-virtualization.sh
)

for s in "${helpers[@]}"; do
  [[ -x $s ]] && run_script "./$s" || echo "Skipping $s (not found or not executable)"
done

###############################################################################
# Bundle & clean-up
###############################################################################
tar -czf "$OUT_TAR" -C "$(dirname "$WORKDIR")" "$(basename "$WORKDIR")"
echo -e "\nSupport bundle written to: $OUT_TAR"

if (( KEEP_WORK )); then
  echo "Temporary files kept in $WORKDIR"
else
  rm -rf "$WORKDIR"
fi

exit 0

