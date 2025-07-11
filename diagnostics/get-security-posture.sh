#!/usr/bin/env bash
# =============================================================================
#  get-security-posture.sh — Quick SELinux/AppArmor, firewall & lockdown audit
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
usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

  -o, --output FILE   Write report to FILE instead of stdout
  -V, --version       Show script version and exit
  -h, --help          This help text
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
# 1. Mandatory Access Control
###############################################################################
hdr "1. Mandatory Access Control"
if have getenforce; then
  printf "SELinux mode : %s\n" "$(getenforce)" >&$OUT_FD
elif [[ -f /sys/fs/selinux/enforce ]]; then
  [[ $(< /sys/fs/selinux/enforce) = 1 ]] && m=Enforcing || m=Permissive
  printf "SELinux mode : %s\n" "$m" >&$OUT_FD
else
  echo  "SELinux      : not enabled" >&$OUT_FD
fi

if have apparmor_status; then
  apparmor_status 2>/dev/null | grep "profiles are in" >&$OUT_FD
elif [[ -d /sys/kernel/security/apparmor ]]; then
  echo "AppArmor     : Enabled (kernel interface present)" >&$OUT_FD
else
  echo "AppArmor     : not enabled" >&$OUT_FD
fi

###############################################################################
# 2. Firewall
###############################################################################
hdr "2. Firewall Rules (first 20 lines)"
if have nft && nft list ruleset &>/dev/null; then
  nft list ruleset 2>/dev/null | head -20 >&$OUT_FD || true
elif have iptables; then
  iptables -S 2>/dev/null | head -20 >&$OUT_FD || true
else
  echo "(no nftables or iptables found)" >&$OUT_FD
fi

###############################################################################
# 3. Listening sockets
###############################################################################
hdr "3. Listening Sockets (TCP/UDP)"
if have ss; then
  ss -H -lntu | awk '{print $1, $5}' | column -t >&$OUT_FD
else
  echo "(ss utility missing)" >&$OUT_FD
fi

###############################################################################
# 4. Kernel lockdown & Secure-Boot
###############################################################################
hdr "4. Kernel Lockdown / Secure-Boot"
[[ -f /sys/kernel/security/lockdown ]] \
  && echo "Lockdown: $(cat /sys/kernel/security/lockdown)" >&$OUT_FD \
  || echo "Lockdown: not supported by this kernel" >&$OUT_FD
if [[ -d /sys/firmware/efi/efivars ]]; then
  efivar --dump 2>/dev/null | grep -qi SecureBootEnabled \
    && echo "UEFI Secure Boot: enabled" >&$OUT_FD \
    || echo "UEFI Secure Boot: disabled/unknown" >&$OUT_FD
else
  echo "UEFI Secure Boot: system not in UEFI mode" >&$OUT_FD
fi

###############################################################################
# 5. Selected kernel-hardening CONFIGs
###############################################################################
hdr "5. Kernel Hardening Options (selected)"
cfg="/boot/config-$(uname -r)"
if [[ -r $cfg ]]; then
  grep -E 'CONFIG_(STRICT_KERNEL_RWX|STRICT_MODULE_RWX|IMPLICIT_FORTIFY)' "$cfg" >&$OUT_FD
else
  echo "(kernel config not accessible)" >&$OUT_FD
fi

###############################################################################
# 6. Disk Encryption (LUKS / dm-crypt)
###############################################################################
hdr "6. Disk Encryption (LUKS / dm-crypt)"
have cryptsetup || { echo "(cryptsetup missing – section skipped)"; hdr "Security posture report complete"; exit 0; }

mapfile -t crypt_devs < <(lsblk -rpno NAME,TYPE | awk '$2=="crypt"{print $1}')
if ((${#crypt_devs[@]}==0)); then
  echo "(no dm-crypt devices found)" >&$OUT_FD
else
  for dev in "${crypt_devs[@]}"; do
    echo "--- ${dev} ---" >&$OUT_FD
    cryptsetup luksDump --dump-volume-key --key-slot - "$dev" 2>/dev/null \
      | grep -E '^(Version|Cipher|Key|UUID|Subsystem|MK bits|[Kk]eyslots)' \
      | sed 's/^/  /' >&$OUT_FD || echo "  (luksDump failed – device may be plain mapper)" >&$OUT_FD
  done
fi

hdr "Security posture report complete"
exit 0

