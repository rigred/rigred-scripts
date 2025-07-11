#!/usr/bin/env bash
# =============================================================================
#  get-ml-stack-info.sh — AI/ML accelerators & software-stack snapshot
#
#  Author  : Rigo Reddig
#  Version : 1.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.0.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

###############################################################################
# CLI
###############################################################################
OUT_FD=1
usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

  -o, --output FILE   Write report to FILE instead of stdout
  -V, --version       Show script version and exit
  -h, --help          This help text

No dependencies are *required*, but data richness improves if these exist:
  • lspci, lsusb, nvidia-smi, rocm-smi, hl-smi, intel-npu-smi, edgetpu_info
  • python3 + frameworks (TensorFlow, PyTorch, JAX, ONNX Runtime …)
EOF
}
while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output) exec 3>"$2"; OUT_FD=3; shift 2;;
    -V|--version) echo "$VERSION"; exit 0;;
    -h|--help)    usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 3;;
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

###############################################################################
# 1. Hardware accelerators (PCI / USB)
###############################################################################
hdr "1. Detected AI/ML Accelerators (PCI & USB)"

if have lspci; then
  lspci -nn |
    grep -Ei 'NVIDIA.*(Tensor|GPU)|AMD.*(Instinct|MI)|Habana|Graphcore|Coral|TPU|Intel.*NPU|Movidius' |
    sed 's/^/  /' >&$OUT_FD || true
else
  echo "(lspci missing)" >&$OUT_FD
fi

if have lsusb; then
  lsusb |
    grep -Ei 'Google.*Coral|Movidius|Edge TPU' |
    sed 's/^/  /' >&$OUT_FD || true
fi

###############################################################################
# 2. Vendor-specific tool snapshots
###############################################################################
hdr "2. Vendor Utilities"

report_tool() {
  local t=$1; shift
  if have "$t"; then
    echo "--- $t ---" >&$OUT_FD
    "$t" "$@" 2>/dev/null | head -20 | sed 's/^/  /' >&$OUT_FD || true
  fi
}

report_tool nvidia-smi
report_tool rocm-smi --showdriverversion --showproductname
report_tool hl-smi                     # Habana Gaudi
report_tool intel-npu-smi
report_tool edgetpu_info               # Coral

###############################################################################
# 3. Acceleration libraries (shared objects present)
###############################################################################
hdr "3. Acceleration Libraries Present"

search_lib() { ls -1 /usr/lib*/"$1"* 2>/dev/null | head -1; }

for lib in libcudnn libnvinfer libopenvino libmkl_sycl libmkl_rt libdnnl libhipblas miopen*; do
  path=$(search_lib "$lib") || true
  [[ -n $path ]] && printf "  %-12s : %s\n" "$lib" "$path" >&$OUT_FD
done

###############################################################################
# 4. Python frameworks & versions
###############################################################################
hdr "4. Python ML Frameworks"

if have python3; then
  python3 - <<'PY' | sed 's/^/  /' >&$OUT_FD
import importlib, sys
pkgs = ['tensorflow','torch','jax','onnxruntime','xgboost','lightgbm','sklearn']
for p in pkgs:
    try:
        mod = importlib.import_module(p)
        ver = getattr(mod, '__version__', 'unknown')
        print(f"{p:<12} : {ver}")
    except Exception:
        pass
PY
else
  echo "(python3 missing)" >&$OUT_FD
fi

###############################################################################
# 5. Kernel / driver modules loaded
###############################################################################
hdr "5. Accelerator Kernel Modules"

lsmod | grep -E 'nvidia|amdgpu|habana|intel_?npu|gcipu|gcipcie' | sed 's/^/  /' >&$OUT_FD || true

hdr "AI/ML stack snapshot complete"
exit 0

