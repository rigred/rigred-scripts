#!/usr/bin/env bash
# =============================================================================
#  get-gpu-info.sh — Cross-vendor GPU inventory, link, VRAM, thermals, full dumps
#
#  Version : 1.2.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.2.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

###############################################################################
# CLI
###############################################################################
OUT_FD=1
usage() { echo "Usage: ${0##*/} [-o FILE] [-V] [-h]"; }
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) exec 3>"$2"; OUT_FD=3; shift 2;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *) echo "Unknown option $1"; usage; exit 3;;
  esac
done

###############################################################################
# Helpers
###############################################################################
have() { command -v "$1" &>/dev/null; }
hdr () {
  printf '\n==============================================================================\n' >&$OUT_FD
  printf ' %s\n' "$1" >&$OUT_FD
  printf '==============================================================================\n' >&$OUT_FD
}
link_info() {                                   # $1 = /sys path to device
  s=$(cat "$1/current_link_speed" 2>/dev/null || echo "N/A")
  w=$(cat "$1/current_link_width" 2>/dev/null || echo "xN/A")
  ms=$(cat "$1/max_link_speed" 2>/dev/null || echo "N/A")
  mw=$(cat "$1/max_link_width" 2>/dev/null || echo "xN/A")
  printf '%s %s (max %s %s)\n' "$s" "$w" "$ms" "$mw"
}

###############################################################################
# 1. Inventory & PCIe link
###############################################################################
hdr "1. GPU PCI Inventory & Link"
have lspci || { echo "lspci missing"; exit 1; }
while read -r slot cls rest; do
  sys="/sys/bus/pci/devices/0000:${slot}"
  printf "%-12s %s\n" "$slot" "$rest" >&$OUT_FD
  printf "  PCIe link   : %s\n" "$(link_info "$sys")" >&$OUT_FD
done < <(lspci -Dnn | grep -Ei 'vga|3d|display')

###############################################################################
# 2. lshw summary
###############################################################################
if have lshw; then
  hdr "2. lshw -C display (brief)"
  lshw -quiet -C display 2>/dev/null | \
    grep -E 'description:|product:|vendor:|configuration: driver=' | \
    sed 's/^/  /' >&$OUT_FD
fi

###############################################################################
# 3. Vendor-specific summary **and full raw dump**
###############################################################################
for slot in $(lspci -Dnn | awk '/VGA|3D|Display/{print $1}'); do
  vendor=$(lspci -s "$slot" -n | awk '{print $3}' | cut -d: -f1)
  devstr=$(lspci -s "$slot" | cut -d' ' -f2-)
  case $vendor in
    10de)  # NVIDIA
      hdr "3.NVIDIA @ $slot — $devstr"
      if have nvidia-smi; then
        # quick summary
        nvidia-smi --format=csv,noheader,nounits \
          --query-gpu=pci.bus_id,memory.total,memory.used,temperature.gpu,fan.speed \
          | awk -F, -v bus="$slot" '
              $1==bus {
                printf "  VRAM total/used : %s/%s MiB\n  Temp/Fan        : %s °C / %s %%\n",
                       $2,$3,$4,$5
              }' >&$OUT_FD
        # full dump
        echo -e "\n  --- nvidia-smi -q (raw) ---" >&$OUT_FD
        nvidia-smi -q -i "$slot" >&$OUT_FD
      else
        echo "(nvidia-smi not installed)" >&$OUT_FD
      fi
      ;;
    1002|1022)  # AMD
      hdr "3.AMD @ $slot — $devstr"
      if have rocm-smi; then
        rocm-smi --showmeminfo vram --json -d "$slot" \
          | jq -r '.card[].VRAM| "  VRAM total/used : \(.Total)/\(.Used) MiB"' >&$OUT_FD
        rocm-smi --showtemp --json -d "$slot" \
          | jq -r '.card[].Temperature.Gpu as $t | "  Temp            : \($t) °C"' >&$OUT_FD
        echo -e "\n  --- rocm-smi --showallinfo (raw) ---" >&$OUT_FD
        rocm-smi --showallinfo -d "$slot" >&$OUT_FD
      elif have radeontop; then
        printf "  (rocm-smi missing, using radeontop snapshot)\n" >&$OUT_FD
        radeontop -d /dev/stdout -l 1 -t >&$OUT_FD
      else
        echo "(AMD utilities missing)" >&$OUT_FD
      fi
      ;;
    8086)  # Intel
      hdr "3.Intel @ $slot — $devstr"
      if have intel_gpu_info; then
        vram=$(intel_gpu_info -q 2>/dev/null | awk '/mappable size/ {gsub(/[^0-9]/,"",$3); print $3}')
        printf "  VRAM (mappable) : %s KiB\n" "$vram" >&$OUT_FD
        echo -e "\n  --- intel_gpu_info -q (raw) ---" >&$OUT_FD
        intel_gpu_info -q >&$OUT_FD
      elif have intel_gpu_top; then
        printf "  (intel_gpu_info missing, 3-s intel_gpu_top JSON)\n" >&$OUT_FD
        timeout 3 intel_gpu_top -J -s 1000 >&$OUT_FD || true
      else
        echo "(Intel GPU tools missing)" >&$OUT_FD
      fi
      ;;
    *) hdr "3.Unknown vendor $vendor @ $slot"; echo "(no parser)" >&$OUT_FD ;;
  esac
done

###############################################################################
# 4. Extra temperatures from lm-sensors
###############################################################################
if have sensors; then
  hdr "4. Additional temperatures (sensors)"
  sensors | grep -E 'GPU|edge|temp[0-9]+' | sed 's/^/  /' >&$OUT_FD
fi

hdr "GPU snapshot complete"
exit 0

