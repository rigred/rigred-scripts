#!/usr/bin/env bash
# =============================================================================
#  get-io-profile.sh — Live I/O saturation & latency snapshot
#
#  Author  : Rigo Reddig
#  Version : 3.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="3.0.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

###############################################################################
# Defaults / globals
###############################################################################
INTERVAL=1
COUNT=5
OUTPUT_FD=1
FMT="pretty"        # pretty | csv | json
COLOR=auto          # auto | always | never
DO_BTT=1
BTT_DEV=""
WARN_UTIL=0         # %util threshold (0 = off)
WARN_RATE=0         # MB/s threshold (0 = off)
EXIT_STATUS=0

###############################################################################
# Usage
###############################################################################
usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

Sampling
  -i, --interval SEC       Seconds between samples (default 1)
  -c, --count    NUM       Number of samples      (default 5)

Output
  -f, --format   FMT       pretty | csv | json    (default pretty)
       --color [auto|always|never]  Colourise hotspots in pretty mode
  -o, --output   FILE      Write report to FILE   (pretty mode only)

Alerts
       --warn-util PCT     Exit 8 if any device %%util >= PCT
       --warn-rate MBPS    Exit 9 if any process total I/O >= MBPS

Latency
  -d, --device   DEV       Run blktrace/BTT on DEV (default: busiest device)
       --no-btt           Skip the blktrace/BTT latency section

Misc
  -V, --version           Show script version and exit
  -h, --help              This help text
EOF
}

###############################################################################
# Parse CLI
###############################################################################
while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--interval) INTERVAL=$2; shift 2;;
    -c|--count)    COUNT=$2;    shift 2;;
    -o|--output)   exec 3>"$2"; OUTPUT_FD=3; shift 2;;
    -f|--format)   FMT=$2; shift 2;;
    --color)
         COLOR=${2:-auto}; [[ $COLOR == auto || $COLOR == always || $COLOR == never ]] || {
           echo "--color expects auto|always|never"; exit 3; }; shift 2;;
    -d|--device)   BTT_DEV=$2; shift 2;;
    --no-btt)      DO_BTT=0; shift;;
    --warn-util)   WARN_UTIL=$2; shift 2;;
    --warn-rate)   WARN_RATE=$2; shift 2;;
    -V|--version)  echo "$VERSION"; exit 0;;
    -h|--help)     usage; exit 0;;
    *) echo "Unknown option $1"; usage; exit 3;;
  esac
done

###############################################################################
# Dependency checks
###############################################################################
need() { command -v "$1" &>/dev/null || { echo "Missing tool: $1"; exit 1; }; }
for t in iostat pidstat awk; do need "$t"; done
have_column=$(command -v column &>/dev/null && echo 1 || echo 0)
have_jq=$(command -v jq &>/dev/null && echo 1 || echo 0)
have_btt_tools=$(command -v blktrace &>/dev/null && command -v blkparse &>/dev/null \
                 && command -v btt &>/dev/null && echo 1 || echo 0)

###############################################################################
# Helpers
###############################################################################
supports_color() {
  [[ $COLOR == never ]] && return 1
  [[ $COLOR == always ]] && return 0
  [[ -t $OUTPUT_FD && $COLOR == auto ]] && return 0
  return 1
}

# ANSI helpers (only used in pretty mode)
c_red=$'\e[31m'; c_yel=$'\e[33m'; c_rst=$'\e[0m'
colorize() { supports_color || { echo "$1"; return; }; echo "${c_red}$1${c_rst}"; }

header() {
  [[ $FMT != pretty ]] && return
  printf '\n==============================================================================\n' >&$OUTPUT_FD
  printf ' %s\n' "$1" >&$OUTPUT_FD
  printf '==============================================================================\n' >&$OUTPUT_FD
}

print_table_pretty() { (( have_column )) && column -t -s $'\t' || cat; }

# temp-file housekeeping
TMP_FILES=()
tmp() { local f; f=$(mktemp); TMP_FILES+=("$f"); echo "$f"; }
trap 'rm -f "${TMP_FILES[@]}" 2>/dev/null' EXIT

###############################################################################
# 1. iostat aggregation
###############################################################################
TMP_IO=$(tmp)
iostat -dxk "$INTERVAL" "$COUNT" >"$TMP_IO"

awk -v OFS='\t' '
  BEGIN { FS="[[:space:]]+" }
  /^Device/ || /^Linux/ || /^[[:space:]]*$/ { next }
  { d=$1; r[d]+=$2; w[d]+=$8; u[d]+=$NF; n[d]++ }
  END {
    for (d in u)
      printf "%s\t%.2f\t%.2f\t%.2f\n", d, r[d]/n[d], w[d]/n[d], u[d]/n[d]
  }' "$TMP_IO" |
  sort -nrk4 |
  head -10 >"$TMP_IO.data"

# auto-pick busiest device if none provided
[[ -z $BTT_DEV && $DO_BTT -eq 1 && -s $TMP_IO.data ]] && BTT_DEV=$(awk 'NR==1{print $1}' "$TMP_IO.data")

###############################################################################
# 2. pidstat aggregation
###############################################################################
TMP_PID=$(tmp)
pidstat -d -p ALL "$INTERVAL" "$COUNT" >"$TMP_PID"

awk -v OFS='\t' '
  /^[0-9]{2}:[0-9]{2}:[0-9]{2}|^Average:/ {
    if ($3=="PID") next
    pid=$3; rd=$4; wr=$5; cmd=$8
    if (pid==0 || cmd=="pidstat") next
    r[pid]+=rd; w[pid]+=wr; n[pid]++; name[pid]=cmd
  }
  END{
    for (p in r){
      ar=r[p]/n[p]; aw=w[p]/n[p]; at=ar+aw
      printf "%s\t%s\t%.1f\t%.1f\t%.1f\n", p, name[p], ar, aw, at
    }
  }' "$TMP_PID" |
  sort -nrk5 |
  head -15 >"$TMP_PID.data"

###############################################################################
# 3. Output section (pretty | csv | json)
###############################################################################
if [[ $FMT == json ]]; then
  need jq
  # devices JSON
  jq -Rn '
    ( input | split("\t") ) as $hdr
    | [ inputs | split("\t") as $row | reduce range(0;$hdr|length) as $i
        ({}; .[$hdr[$i]] = ($row[$i]|tonumber? // $row[$i]) )
      ]' <"$TMP_IO.data" >"$TMP_IO.json"
  # processes JSON
  jq -Rn '
    ( ["PID","COMMAND","avg_rdKBs","avg_wrKBs","avg_totKBs"] ) as $hdr
    | [ inputs | split("\t") as $row | reduce range(0;$hdr|length) as $i
        ({}; .[$hdr[$i]] = ($row[$i]|tonumber? // $row[$i]) )
      ]' <"$TMP_PID.data" >"$TMP_PID.json"

  jq -n --slurpfile dev "$TMP_IO.json" \
         --slurpfile proc "$TMP_PID.json" \
         '{devices:$dev[0], processes:$proc[0]}' >&$OUTPUT_FD
  exit 0
fi

if [[ $FMT == csv ]]; then
  # Devices
  echo "Device,r/s,w/s,%util" >&$OUTPUT_FD
  sed 's/\t/,/g' "$TMP_IO.data" >&$OUTPUT_FD
  echo "" >&$OUTPUT_FD
  # Processes
  echo "PID,COMMAND,avg_rdKB/s,avg_wrKB/s,avg_totKB/s" >&$OUTPUT_FD
  sed 's/\t/,/g' "$TMP_PID.data" >&$OUTPUT_FD
  exit 0
fi

# --- pretty output with optional ANSI colour ---------------------------------
header "1. Top I/O devices — iostat -dx ${INTERVAL} ${COUNT} (averaged)"
(
  printf "Device\tr/s\tw/s\t%%util\n"
  while IFS=$'\t' read -r dev rs ws ut; do
    if (( WARN_UTIL > 0 && ${ut%.*} >= WARN_UTIL )); then
      printf "%s\t%s\t%s\t%s\n" "$(colorize "$dev")" "$(colorize "$rs")" "$(colorize "$ws")" "$(colorize "$ut")"
      EXIT_STATUS=8
    else
      printf "%s\t%s\t%s\t%s\n" "$dev" "$rs" "$ws" "$ut"
    fi
  done <"$TMP_IO.data"
) | print_table_pretty >&$OUTPUT_FD || true

header "2. Top processes by disk I/O — pidstat -d ${INTERVAL} ${COUNT}"
(
  printf "PID\tCOMMAND\tavg_rdKB/s\tavg_wrKB/s\tavg_totKB/s\n"
  while IFS=$'\t' read -r pid cmd rd wr tot; do
    mbps=$(awk "BEGIN{print $tot/1024}")
    if (( WARN_RATE > 0 && ${mbps%.*} >= WARN_RATE )); then
      printf "%s\t%s\t%s\t%s\t%s\n" "$(colorize "$pid")" "$(colorize "$cmd")" \
              "$(colorize "$rd")" "$(colorize "$wr")" "$(colorize "$tot")"
      EXIT_STATUS=9
    else
      printf "%s\t%s\t%s\t%s\t%s\n" "$pid" "$cmd" "$rd" "$wr" "$tot"
    fi
  done <"$TMP_PID.data"
) | print_table_pretty >&$OUTPUT_FD || true

###############################################################################
# 4. Latency histogram (pretty mode only)
###############################################################################
if (( DO_BTT )) && (( have_btt_tools )); then
  [[ $BTT_DEV == /dev/* ]] || BTT_DEV="/dev/$BTT_DEV"         # <-- add prefix
  if [[ -b $BTT_DEV ]]; then
    header "3. blktrace latency histogram (10 s on ${BTT_DEV##*/})"
    TMP_DIR=$(mktemp -d); TMP_FILES+=("$TMP_DIR/trace.bin" "$TMP_DIR/out")

    # Temporarily disable ERR trap so a non-zero exit from blktrace/blkparse
    # doesn’t abort the whole script.
    set +e
    blktrace -a issue -d "$BTT_DEV" -w 10 -o - 2>/dev/null \
      | blkparse -i - -d "$TMP_DIR/trace.bin" 2>/dev/null
    blk_rc=$?
    set -e

    if (( blk_rc == 0 )) && btt -i "$TMP_DIR/trace.bin" >"$TMP_DIR/out" 2>/dev/null && [[ -s $TMP_DIR/out ]]; then
      cat "$TMP_DIR/out" >&$OUTPUT_FD
    else
      echo "No latency events captured (or blktrace unsupported on ${BTT_DEV##*/})." >&$OUTPUT_FD
    fi
  else
    header "3. blktrace skipped — ${BTT_DEV##*/} is not a block device"
  fi
elif (( DO_BTT )); then
  header "3. blktrace section skipped (install blktrace suite)"
fi

header "I/O Profile Complete"

exit $EXIT_STATUS

