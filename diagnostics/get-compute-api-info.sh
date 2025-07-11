#!/usr/bin/env bash
# =============================================================================
#  get-compute-api-info.sh — Detect and summarise installed GPU/accelerator
#                            compute stacks (CUDA, ROCm, OpenCL, SYCL, etc.)
#
#  Author  : Rigo Reddig
#  Version : 1.0.0  (2025-07-11)
#  License : MIT
# =============================================================================
set -Eeuo pipefail; IFS=$'\n\t'
VERSION="1.0.0"
trap 'printf "Error on line %d.  Aborting.\n" "$LINENO" >&2' ERR

###############################################################################
# CLI
###############################################################################
OUT_FD=1
usage() {
  cat <<EOF
Usage: ${0##*/} [-o FILE] [-V] [-h]

  -o, --output FILE   Write report to FILE instead of stdout
  -V, --version       Show script version and exit
  -h, --help          This help text

No tools are strictly required, but the report becomes richer when one or more
of the following are installed:

  • nvidia-smi (CUDA)   • rocminfo / rocm-smi (ROCm/HIP)
  • clinfo (OpenCL)     • sycl-ls (SYCL)            • vulkaninfo
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
hdr() { printf '\n==============================================================================\n %s\n==============================================================================\n' "$1" >&$OUT_FD; }

###############################################################################
# 1. CUDA
###############################################################################
hdr "1. NVIDIA CUDA"
if have nvidia-smi; then
  nvidia-smi --query-gpu=driver_version,cuda_version,name --format=csv,noheader,nounits \
    | while IFS=',' read -r drv cuda name; do
        printf "GPU : %s\nDriver : %s  CUDA : %s\n\n" "$name" "$drv" "$cuda" >&$OUT_FD
      done
else
  echo "(nvidia-smi not found — CUDA runtime likely absent)" >&$OUT_FD
fi

###############################################################################
# 2. AMD ROCm / HIP
###############################################################################
hdr "2. AMD ROCm / HIP"
if have rocminfo; then
  rocminfo | grep -E 'Name:|gfx' | head -10 | sed 's/^/  /' >&$OUT_FD
elif have rocm-smi; then
  rocm-smi --showproductname --showdriverversion | sed 's/^/  /' >&$OUT_FD
else
  echo "(ROCm utilities not installed)" >&$OUT_FD
fi

###############################################################################
# 3. OpenCL platforms & devices
###############################################################################
hdr "3. OpenCL (clinfo)"
if have clinfo; then
  clinfo -l | sed 's/^/  /' >&$OUT_FD
else
  echo "(clinfo missing)" >&$OUT_FD
fi

###############################################################################
# 4. SYCL / oneAPI
###############################################################################
hdr "4. SYCL / oneAPI"
if have sycl-ls; then
  sycl-ls --verbose | sed 's/^/  /' >&$OUT_FD
else
  echo "(sycl-ls not available)" >&$OUT_FD
fi

###############################################################################
# 5. Vulkan – compute-capable queue families
###############################################################################
hdr "5. Vulkan compute queues"
if have vulkaninfo; then
  vulkaninfo --summary | grep -A1 "Compute" | sed 's/^/  /' >&$OUT_FD
else
  echo "(vulkaninfo missing)" >&$OUT_FD
fi

hdr "Compute-API snapshot complete"
exit 0

