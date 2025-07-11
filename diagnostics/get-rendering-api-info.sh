#!/usr/bin/env bash
# =============================================================================
#  get-rendering-api-info.sh — Inventory of OpenGL, EGL, Vulkan & windowing
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

Optional tools probed:

  • glxinfo (OpenGL / GLX)  • eglinfo / weston-info (EGL / Wayland)
  • vulkaninfo             • xdpyinfo / wayland-info
EOF
}

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
hdr() { printf '\n==============================================================================\n %s\n==============================================================================\n' "$1" >&$OUT_FD; }

###############################################################################
# 1. OpenGL (GLX)
###############################################################################
hdr "1. OpenGL / GLX"
if have glxinfo; then
  glxinfo -B | sed 's/^/  /' >&$OUT_FD
else
  echo "(glxinfo missing — likely headless or Wayland-only)" >&$OUT_FD
fi

###############################################################################
# 2. EGL & Wayland
###############################################################################
hdr "2. EGL / Wayland"
if have eglinfo; then
  eglinfo --version | sed 's/^/  /' >&$OUT_FD
fi
if have weston-info; then
  weston-info | head -10 | sed 's/^/  /' >&$OUT_FD
elif have wayland-info; then
  wayland-info | head -10 | sed 's/^/  /' >&$OUT_FD
else
  echo "(no Wayland info tool found)" >&$OUT_FD
fi

###############################################################################
# 3. Vulkan – graphics features
###############################################################################
hdr "3. Vulkan graphics info"
if have vulkaninfo; then
  vulkaninfo --summary | grep -A1 "Graphics" | sed 's/^/  /' >&$OUT_FD
else
  echo "(vulkaninfo missing)" >&$OUT_FD
fi

###############################################################################
# 4. Display server / compositor
###############################################################################
hdr "4. Active display server"
if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  echo "Wayland session : \$WAYLAND_DISPLAY=$WAYLAND_DISPLAY" >&$OUT_FD
elif [[ -n ${DISPLAY:-} ]]; then
  echo "X11 session     : \$DISPLAY=$DISPLAY" >&$OUT_FD
else
  echo "(no GUI session detected)" >&$OUT_FD
fi

hdr "Graphics-API snapshot complete"
exit 0

